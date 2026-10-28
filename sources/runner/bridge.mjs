// The app side of the 时光源 bridge, in Node: every `callHandler(name, ...)` the page makes lands in one of the
// handlers of createHandlers(). Behaviour follows app/lib/util/source/{baswebview,http,cache,webview}.dart.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const DEFAULT_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';

function hostOf(url) {
  try {
    return new URL(url.replace(/^https?2:\/\//i, 'https://')).host.toLowerCase();
  } catch {
    return String(url).toLowerCase();
  }
}

/** A JSON file that is read once and written on every change. */
class JsonFile {
  constructor(file, init) {
    this.file = file;
    this.data = init;
    if (file && fs.existsSync(file)) {
      try {
        this.data = JSON.parse(fs.readFileSync(file, 'utf8'));
      } catch {}
    }
  }

  save() {
    if (!this.file) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(this.file, JSON.stringify(this.data, null, 1));
  }
}

/** Cookies by host (`host -> {name: value}`); a cookie set for `example.com` is sent to its subdomains too. */
export class CookieJar extends JsonFile {
  constructor(file) {
    super(file, {});
  }

  #hosts(url) {
    const h = hostOf(url);
    return Object.keys(this.data).filter((k) => h === k || h.endsWith('.' + k));
  }

  /** All cookies that apply to `url` as `{name: value}`. */
  map(url) {
    const out = {};
    for (const k of this.#hosts(url).sort((a, b) => a.length - b.length)) Object.assign(out, this.data[k]);
    return out;
  }

  header(url) {
    return Object.entries(this.map(url)).map(([k, v]) => `${k}=${v}`).join('; ');
  }

  static parseText(text) {
    const out = {};
    for (const part of String(text ?? '').split(';')) {
      const i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
    }
    return out;
  }

  /** Replaces the cookies of the url's host with `text` (`a=b; c=d`). */
  set(url, text) {
    this.data[hostOf(url)] = CookieJar.parseText(text);
    this.save();
  }

  setOne(url, name, value) {
    const h = hostOf(url);
    this.data[h] = { ...(this.data[h] ?? {}), [name]: String(value) };
    this.save();
  }

  remove(url) {
    delete this.data[hostOf(url)];
    this.save();
  }

  /** Stores the `Set-Cookie` headers of a response. */
  store(url, setCookies) {
    const host = hostOf(url);
    for (const sc of setCookies ?? []) {
      const [pair, ...attrs] = sc.split(';');
      const i = pair.indexOf('=');
      if (i <= 0) continue;
      const name = pair.slice(0, i).trim();
      const value = pair.slice(i + 1).trim();
      let domain = host;
      let expired = false;
      for (const a of attrs) {
        const [k, v = ''] = a.trim().split('=');
        if (k.toLowerCase() === 'domain' && v) domain = v.trim().replace(/^\./, '').toLowerCase();
        if (k.toLowerCase() === 'max-age' && Number(v) <= 0) expired = true;
        if (k.toLowerCase() === 'expires' && v && Date.parse(v) < Date.now()) expired = true;
      }
      this.data[domain] = this.data[domain] ?? {};
      if (expired) delete this.data[domain][name];
      else this.data[domain][name] = value;
    }
    this.save();
  }
}

/** The page's cache.* store: one text per key. */
export class KvCache extends JsonFile {
  constructor(file) {
    super(file, {});
  }

  get(key) {
    return Object.hasOwn(this.data, key) ? this.data[key] : null;
  }

  set(key, value) {
    this.data[key] = String(value ?? '');
    this.save();
  }

  remove(key) {
    delete this.data[key];
    this.save();
  }
}

// ---------------------------------------------------------------- charset

function charsetOf(contentType, bytes) {
  const m = /charset=["']?([\w-]+)/i.exec(contentType ?? '');
  if (m) return m[1].toLowerCase();
  const head = Buffer.from(bytes.subarray(0, 4096)).toString('latin1');
  const m2 = /<meta[^>]+charset=["']?\s*([\w-]+)/i.exec(head) ?? /<\?xml[^>]+encoding=["']([\w-]+)/i.exec(head);
  return m2 ? m2[1].toLowerCase() : 'utf-8';
}

export function decodeBody(bytes, contentType) {
  let label = charsetOf(contentType, bytes);
  if (label === 'gb2312' || label === 'gbk') label = 'gb18030';
  try {
    return new TextDecoder(label, { fatal: false }).decode(bytes);
  } catch {
    return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  }
}

let gbkTable = null;
function gbkEncoder() {
  if (gbkTable) return gbkTable;
  gbkTable = new Map();
  const dec = new TextDecoder('gb18030', { fatal: false });
  const b = new Uint8Array(2);
  for (let lead = 0x81; lead <= 0xfe; lead++) {
    for (let trail = 0x40; trail <= 0xfe; trail++) {
      if (trail === 0x7f) continue;
      b[0] = lead;
      b[1] = trail;
      const ch = dec.decode(b);
      if (ch.length === 1 && ch !== '�' && !gbkTable.has(ch)) gbkTable.set(ch, (lead << 8) | trail);
    }
  }
  return gbkTable;
}

/** The page's `utf8ToGbkUrlEncoded`: GBK bytes, percent-encoded (ASCII as encodeURIComponent writes it). */
export function gbkUrlEncode(str) {
  const table = gbkEncoder();
  let out = '';
  for (const ch of String(str)) {
    const code = ch.codePointAt(0);
    if (code < 0x80) {
      out += encodeURIComponent(ch);
      continue;
    }
    const v = table.get(ch);
    if (v === undefined) out += '%3F';
    else out += '%' + (v >> 8).toString(16).toUpperCase().padStart(2, '0') + '%' + (v & 0xff).toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

// ---------------------------------------------------------------- http

function parseHeaders(h) {
  if (h == null) return {};
  let v = h;
  if (typeof v === 'string') {
    const t = v.trim();
    if (!t.startsWith('{')) return {};
    try {
      v = JSON.parse(t);
    } catch {
      return {};
    }
  }
  const out = {};
  if (v && typeof v === 'object') for (const [k, val] of Object.entries(v)) out[String(k)] = val == null ? '' : String(val);
  return out;
}

function truthy(v, def) {
  if (v == null) return def;
  if (typeof v === 'boolean') return v;
  const s = String(v);
  return !(s === 'false' || s === '0' || s === '');
}

/**
 * One request of the page (`http` handler). Answers the Response shape of the app:
 * `{method, data, body (base64), headers {name: [values]}, statusCode, statusMessage}`; failures give statusCode 0.
 */
export async function httpRequest({ method, url, body = '', headers, followRedirects, contentType = '' }, { jar, isCookieJar = true, timeoutMs = 100000, ua = DEFAULT_UA, log } = {}) {
  const m = (String(method ?? '').trim().toLowerCase() || 'get');
  const result = (o) => ({ method: m, data: '', body: '', headers: {}, statusCode: 0, statusMessage: '', ...o });
  try {
    let target = String(url).trim().replace(/^http2:\/\//i, 'https://').replace(/^https2:\/\//i, 'https://');
    const h = parseHeaders(headers);
    if (m === 'post') {
      const key = Object.keys(h).find((k) => k.toLowerCase() === 'content-type') ?? '';
      if (contentType.trim()) {
        if (key) delete h[key];
        h['Content-Type'] = contentType.trim();
      } else if (!key) h['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (!Object.keys(h).some((k) => k.toLowerCase() === 'user-agent')) h['User-Agent'] = ua;
    // stored cookies of the host, the page's own Cookie header wins (getheader 0xe8bfa8)
    const cookieKey = Object.keys(h).find((k) => k.toLowerCase() === 'cookie');
    if (jar) {
      const merged = { ...jar.map(target), ...CookieJar.parseText(cookieKey ? h[cookieKey] : '') };
      if (cookieKey) delete h[cookieKey];
      const text = Object.entries(merged).map(([k, v]) => `${k}=${v}`).join('; ');
      if (text) h['Cookie'] = text;
    }
    const follow = truthy(followRedirects, true);
    let res;
    let curMethod = m.toUpperCase();
    let curBody = m === 'post' ? body : undefined;
    for (let hop = 0; hop < 11; hop++) {
      if (hop === 10) throw new Error('重定向次数过多');
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), timeoutMs);
      try {
        res = await fetch(target, { method: curMethod, headers: h, body: curBody, redirect: 'manual', signal: ctl.signal });
      } finally {
        clearTimeout(timer);
      }
      if (jar && isCookieJar) jar.store(target, res.headers.getSetCookie?.() ?? []);
      log?.(`http ${curMethod} ${target} -> ${res.status}`);
      const loc = res.headers.get('location');
      if (!follow || !loc || ![301, 302, 303, 307, 308].includes(res.status)) break;
      target = new URL(loc, target).href;
      if (res.status !== 307 && res.status !== 308) {
        curMethod = 'GET';
        curBody = undefined;
        delete h['Content-Type'];
      }
      if (jar) {
        const text = jar.header(target);
        if (text) h['Cookie'] = text;
        else delete h['Cookie'];
      }
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    const hdrs = {};
    for (const [k, v] of res.headers.entries()) (hdrs[k] ??= []).push(v);
    const sc = res.headers.getSetCookie?.() ?? [];
    if (sc.length) hdrs['set-cookie'] = sc;
    return result({
      data: m === 'head' ? '' : decodeBody(bytes, res.headers.get('content-type')),
      body: Buffer.from(bytes).toString('base64'),
      headers: hdrs,
      statusCode: res.status,
      statusMessage: res.statusText,
    });
  } catch (e) {
    log?.(`http error ${url}: ${e.message ?? e}`);
    return result({ statusMessage: String(e.message ?? e) });
  }
}

export function stripTags(html) {
  return String(html ?? '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

const arg = (a, i) => (i < a.length && a[i] != null ? (typeof a[i] === 'string' ? a[i] : typeof a[i] === 'object' ? JSON.stringify(a[i]) : String(a[i])) : '');

/**
 * The handler table. `ctx`: sourceUrl, jar (CookieJar), cache (KvCache), shared (KvCache), log(line), text(type, html),
 * toast(msg), onReady(isCookieJar), onCall(id, value), ua, device, deviceId, webview(req) -> Promise<string>,
 * browser(req) -> Promise<string>, addbook(book), state (plain object for notes).
 */
export function createHandlers(ctx) {
  const log = (s) => ctx.log?.(s);
  const note = (name, a) => log(`[${name}] ${a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(', ').slice(0, 300)}`);
  const H = {
    CookieJar: (a) => {
      ctx.onReady?.(a.length ? truthy(a[0], true) : true);
      return null;
    },
    call: (a) => {
      ctx.onCall?.(arg(a, 0), a.length > 1 ? a[1] : null);
      return null;
    },
    refreshExplore: (a) => {
      note('refreshExplore', a);
      ctx.state.refreshExplore = (ctx.state.refreshExplore ?? 0) + 1;
      return '';
    },
    setHtml: (a) => {
      note('setHtml', [arg(a, 0).slice(0, 80) + '…']);
      return null;
    },
    buildNumber: () => '1026',
    version: () => '2.2.1026',
    id: () => ctx.deviceId,
    device: () => ctx.device ?? 'ios',
    getLoginUser: () => ctx.loginUser ?? '',
    log: (a) => {
      log(`log: ${arg(a, 0)}`);
      return true;
    },
    text: (a) => {
      ctx.text?.(Number(arg(a, 0)) || 0, arg(a, 1));
      return true;
    },
    showToast: (a) => {
      ctx.toast?.(arg(a, 0));
      return true;
    },
    showLongToast: (a) => {
      ctx.toast?.(arg(a, 0));
      return true;
    },
    getWebViewUA: () => ctx.ua ?? DEFAULT_UA,
    openurl: (a) => {
      note('openurl', a);
      return false;
    },
    http: (a) => httpRequest(
      { method: arg(a, 0), url: arg(a, 1), body: arg(a, 2), headers: arg(a, 3), followRedirects: a.length > 4 ? a[4] : true, contentType: arg(a, 5) },
      { jar: ctx.jar, isCookieJar: ctx.isCookieJar ?? true, ua: ctx.ua ?? DEFAULT_UA, log, timeoutMs: ctx.httpTimeoutMs ?? 100000 },
    ),
    'cache.get': (a) => ctx.cache.get(arg(a, 0)),
    'cache.set': (a) => {
      ctx.cache.set(arg(a, 0), arg(a, 1));
      return null;
    },
    'cache.remove': (a) => {
      ctx.cache.remove(arg(a, 0));
      return null;
    },
    'cache.allget': (a) => ctx.shared.get(arg(a, 0)),
    'cache.allset': (a) => {
      ctx.shared.set(arg(a, 0), arg(a, 1));
      return null;
    },
    'cache.allremove': (a) => {
      ctx.shared.remove(arg(a, 0));
      return null;
    },
    'cookie.get': (a) => ctx.jar.header(arg(a, 0)),
    'cookie.getCookie': (a) => {
      const v = ctx.jar.map(arg(a, 0))[arg(a, 1)];
      return v == null || v === '' ? null : v;
    },
    'cookie.remove': (a) => {
      ctx.jar.remove(arg(a, 0));
      return null;
    },
    'cookie.set': (a) => {
      ctx.jar.set(arg(a, 0), arg(a, 1));
      return null;
    },
    'cookie.setcookie': (a) => {
      ctx.jar.setOne(arg(a, 0), arg(a, 1), arg(a, 2));
      return null;
    },
    webview: (a) => ctx.webview({ url: arg(a, 0), js: arg(a, 1), html: arg(a, 2), body: arg(a, 3), headers: parseHeaders(arg(a, 4)), overrideUrlRegex: arg(a, 5), urlregex: arg(a, 6) }),
    webviewajax: (a) => ctx.webview({ url: arg(a, 0), html: arg(a, 1), body: arg(a, 2), headers: parseHeaders(arg(a, 3)), ajaxregex: arg(a, 4) }),
    startBrowser: (a) => ctx.browser({ url: arg(a, 0), title: arg(a, 1), headers: parseHeaders(arg(a, 2)) }),
    startBrowserWithShouldOverrideUrlLoading: (a) => ctx.browser({ url: arg(a, 0), title: arg(a, 1), headers: parseHeaders(arg(a, 2)), override: true }),
    startBrowserDp: (a) => {
      note('startBrowserDp (half sheet, nothing shown here)', a);
      ctx.state.dp = [...(ctx.state.dp ?? []), { url: arg(a, 0), title: arg(a, 1) }];
      return null;
    },
    startBrowserDpWithShouldOverrideUrlLoading: (a) => {
      note('startBrowserDpWithShouldOverrideUrlLoading', a);
      return null;
    },
    startBrowserDpwithHtml: (a) => {
      note('startBrowserDpwithHtml', [arg(a, 0), arg(a, 2)]);
      return null;
    },
    base64encode: (a) => Buffer.from(arg(a, 0), 'utf8').toString('base64'),
    base64decode: (a) => {
      try {
        return Buffer.from(arg(a, 0).trim(), 'base64').toString('utf8');
      } catch {
        return '';
      }
    },
    htmlToText: (a) => stripTags(arg(a, 0)),
    utf8ToGbkUrlEncoded: (a) => gbkUrlEncode(arg(a, 0)),
    getVerificationCode: (a) => {
      note('getVerificationCode (no user here, answering "")', a);
      return '';
    },
    addbook: (a) => {
      note('addbook', a);
      ctx.state.addbook = [...(ctx.state.addbook ?? []), arg(a, 0)];
      ctx.addbook?.(arg(a, 0));
      return null;
    },
    searchbook: (a) => {
      note('searchbook', a);
      return null;
    },
    toTraditional: (a) => arg(a, 0),
    toSimplified: (a) => arg(a, 0),
    showvideoplay: (a) => {
      note('showvideoplay', a);
      return null;
    },
    voice: (a) => {
      note('voice', a);
      return null;
    },
    getdurChapterIndex: () => 0,
    refreshContent: () => null,
    getsourceurl: () => ctx.sourceUrl,
    getWidth: () => 390,
    getHeight: () => 844,
    getsearch: () => -1,
    getReadBook: () => null,
    getsvg: () => '[]',
    showsvg: () => null,
    addsvg: () => null,
    putLyric: () => null,
    getDirectoryList: () => [],
  };
  return H;
}

export function md5(s) {
  return crypto.createHash('md5').update(String(s)).digest('hex');
}
