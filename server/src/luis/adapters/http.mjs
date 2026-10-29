// Shared fetching for the site adapters: one client per upstream with a minimum interval between requests (the sites
// rate-limit and serve captcha pages when hammered), browser-like headers, timeouts, one retry with back-off on
// transport / 5xx failures, charset-aware decoding (GB18030 sites), and small HTML helpers.
// Transport: node:http(s) with the lenient header parser (undici's fetch rejects 七猫's responses: "Unexpected whitespace
// after header value"), manual redirects, gzip / deflate / br; tests inject `fetchImpl` and get the fetch path instead.
import http from 'node:http';
import https from 'node:https';
import zlib from 'node:zlib';

export const UA_DESKTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
export const UA_MOBILE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

export class HttpError extends Error {
  constructor(status, url, text = '') {
    super(`HTTP ${status} ${url}`);
    this.status = status;
    this.url = url;
    this.text = text;
  }
}

/**
 * createClient({ ua, referer, minIntervalMs, timeoutMs, retries, fetchImpl }) -> { get(url, {headers, charset, accept}) }
 * get() answers { status, text, headers }; non-2xx answers throw HttpError (with the body text).
 */
/** One request over node:http(s): lenient header parsing, redirects (5), content decoding. Resolves {status, bytes, headers}. */
export function nodeRequest(url, { method = 'GET', headers = {}, body, timeoutMs = 20000, redirects = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const mod = u.protocol === 'http:' ? http : https;
    const req = mod.request(u, { method, headers: { ...headers, 'Accept-Encoding': 'gzip, deflate, br' }, insecureHTTPParser: true, timeout: timeoutMs }, (res) => {
      const status = res.statusCode ?? 0;
      const loc = res.headers.location;
      if ([301, 302, 303, 307, 308].includes(status) && loc && redirects > 0) {
        res.resume();
        const next = new URL(loc, url).href;
        const keep = status === 307 || status === 308;
        resolve(nodeRequest(next, { method: keep ? method : 'GET', headers, body: keep ? body : undefined, timeoutMs, redirects: redirects - 1 }));
        return;
      }
      const enc = String(res.headers['content-encoding'] ?? '').toLowerCase();
      let stream = res;
      if (enc.includes('br')) stream = res.pipe(zlib.createBrotliDecompress());
      else if (enc.includes('gzip')) stream = res.pipe(zlib.createGunzip());
      else if (enc.includes('deflate')) stream = res.pipe(zlib.createInflate());
      const chunks = [];
      stream.on('data', (c) => chunks.push(c));
      stream.on('error', reject);
      stream.on('end', () => resolve({ status, bytes: new Uint8Array(Buffer.concat(chunks)), headers: new Headers(Object.entries(res.headers).filter(([, v]) => typeof v === 'string').map(([k, v]) => [k, v])) }));
    });
    req.on('timeout', () => req.destroy(new Error(`timeout after ${timeoutMs} ms: ${url}`)));
    req.on('error', reject);
    if (body != null) req.write(body);
    req.end();
  });
}

export function createClient({ ua = UA_DESKTOP, referer = '', minIntervalMs = 400, timeoutMs = 20000, retries = 1, fetchImpl = null, now = Date.now, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
  let chain = Promise.resolve();
  let lastStart = -Infinity;

  function schedule() {
    const slot = chain.then(async () => {
      const wait = lastStart + minIntervalMs - now();
      if (wait > 0) await sleep(wait);
      lastStart = now();
    });
    chain = slot.catch(() => {});
    return slot;
  }

  async function once(url, { headers = {}, charset = '', accept = 'text/html,application/json;q=0.9,*/*;q=0.8', method = 'GET', body } = {}) {
    await schedule();
    const h = { 'User-Agent': ua, Accept: accept, 'Accept-Language': 'zh-CN,zh;q=0.9', ...(referer ? { Referer: referer } : {}), ...headers };
    let status;
    let bytes;
    let resHeaders;
    if (fetchImpl) {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), timeoutMs);
      try {
        const res = await fetchImpl(url, { method, body, redirect: 'follow', signal: ctl.signal, headers: h });
        status = res.status;
        bytes = new Uint8Array(await res.arrayBuffer());
        resHeaders = res.headers;
      } finally {
        clearTimeout(timer);
      }
    } else {
      ({ status, bytes, headers: resHeaders } = await nodeRequest(url, { method, headers: h, body, timeoutMs }));
    }
    const text = decode(bytes, charset || charsetOf(resHeaders.get('content-type'), bytes));
    if (status < 200 || status >= 300) throw new HttpError(status, url, text.slice(0, 2000));
    return { status, text, headers: resHeaders };
  }

  async function get(url, opts = {}) {
    let attempt = 0;
    for (;;) {
      try {
        return await once(url, opts);
      } catch (e) {
        const retriable = !(e instanceof HttpError) || e.status >= 500 || e.status === 429;
        if (!retriable || attempt >= retries) throw e;
        attempt++;
        await sleep(1000 * attempt);
      }
    }
  }

  return { get, ua };
}

export function charsetOf(contentType, bytes) {
  const m = /charset=["']?([\w-]+)/i.exec(contentType ?? '');
  if (m) return m[1].toLowerCase();
  const head = Buffer.from(bytes.subarray(0, 4096)).toString('latin1');
  const m2 = /<meta[^>]+charset=["']?\s*([\w-]+)/i.exec(head);
  return m2 ? m2[1].toLowerCase() : 'utf-8';
}

export function decode(bytes, label) {
  let l = (label || 'utf-8').toLowerCase();
  if (l === 'gb2312' || l === 'gbk') l = 'gb18030';
  try {
    return new TextDecoder(l, { fatal: false }).decode(bytes);
  } catch {
    return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  }
}

/** GB18030 percent-encoding of text (晋江's search takes the keyword that way). */
let gbkTable = null;
export function gbkEncode(str) {
  if (!gbkTable) {
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
  }
  let out = '';
  for (const ch of String(str)) {
    const code = ch.codePointAt(0);
    if (code < 0x80) {
      out += encodeURIComponent(ch);
      continue;
    }
    const v = gbkTable.get(ch);
    out += v === undefined ? '%3F' : '%' + (v >> 8).toString(16).toUpperCase().padStart(2, '0') + '%' + (v & 0xff).toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

// ---------------------------------------------------------------- html helpers

const ENTITIES = { nbsp: ' ', lt: '<', gt: '>', quot: '"', amp: '&', apos: "'", ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', hellip: '…', mdash: '—', middot: '·' };

export function decodeEntities(s) {
  return String(s ?? '')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&([a-z]+);/gi, (m, name) => ENTITIES[name.toLowerCase()] ?? m);
}

/** Tag-less, entity-decoded, whitespace-collapsed text of an html fragment. */
export function text(html) {
  return decodeEntities(String(html ?? '').replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

/** The html as text lines: <br>, </p>, </div>, </h*> and </li> end a line; blank lines dropped. */
export function lines(html) {
  const t = decodeEntities(
    String(html ?? '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|h[1-6]|li|tr|section)>/gi, '\n')
      .replace(/<[^>]+>/g, ''),
  );
  // paragraph indents (ideographic spaces) are dropped: the reader indents paragraphs itself
  return t.split('\n').map((l) => l.replace(/[\s　]+$/g, '').replace(/^[ \t\r　]+/, '')).filter((l) => l.trim());
}

/** First capture group of `re` in html ('' when absent). */
export function find(html, re, group = 1) {
  const m = re.exec(html);
  return m ? (m[group] ?? '').trim() : '';
}

/** All matches of a global regex as arrays of groups. */
export function all(html, re) {
  const out = [];
  const r = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
  let m;
  while ((m = r.exec(html))) out.push(m.slice(1));
  return out;
}

export function abs(base, href) {
  try {
    return new URL(String(href ?? ''), base).href;
  } catch {
    return String(href ?? '');
  }
}
