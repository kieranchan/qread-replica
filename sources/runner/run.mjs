#!/usr/bin/env node
// Desktop runner for 时光源 pages: loads the page in headless Chrome and plays the app (bridge handlers in Node, the same
// entry points, timeouts and result handling as app/lib/util/source/run.dart). Needs Node >= 22 and Chrome or Edge.
//
//   node run.mjs --page <file|url> [--base <bookSourceUrl>] [options] <command> [args]
//
// commands
//   ready                       load the page and wait for its CookieJar call
//   finds                       getfinds()
//   find <url> [page]           find(url, page)
//   search <key> [page] [env]   search(key, page, env)     env: search | searchone
//   info <bookUrl>              info(bookUrl)
//   chapter <tocUrl> [bookUrl]  chapter(tocUrl, bookUrl)
//   content <url> [bookUrl] [i] content(url, bookUrl, index)
//   help | loginurl | login | filter | findfilter <url> | pay <bookUrl> <url>
//   event <name> [bookJson]     callbackjs(name, bookJson)
//   action <js>                 an explore entry's action (runs the js in the page)
//   js <expr>                   any expression, awaited
//   flow <key> [n] [chapterIndex]   search -> info -> chapter -> content of book n
// options
//   --base <url>        the address the page is loaded under = the source's bookSourceUrl (default: the page url,
//                       http://localhost/ for a file)
//   --state <dir>       cache + cookies of this source (default .state/<md5(base)>)
//   --cookie <url> "<a=b; c=d>"   seed cookies (repeatable)      --cache <key> <value>   seed a cache value (repeatable)
//   --aes-key <16 chars>  key of @aes pages (or env QREAD_SOURCE_AES_KEY)
//   --timeout <s>       override every entry-point timeout      --headful   show the browser
//   --device ios|android|macos|windows   --ua <string>   --json (raw value only on stdout)   --quiet (no bridge log)
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CDP, newPage, closePage, withTimeout } from './cdp.mjs';
import { launchChrome } from './chrome.mjs';
import { CookieJar, KvCache, createHandlers, DEFAULT_UA, md5 } from './bridge.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export const TIMEOUTS = { search: 120000, info: 120000, chapter: 400000, content: 120000, finds: 120000, find: 120000, login: 120000, pay: 120000, image: 60000, help: 20000, ready: 60000 };

const SHIM = `(() => {
  if (window.flutter_inappwebview) return;
  const pending = new Map();
  let seq = 0;
  window.__qydResolve = (id, ok, value) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    if (ok) p.resolve(value); else p.reject(new Error(String(value)));
  };
  window.flutter_inappwebview = {
    callHandler(name, ...args) {
      return new Promise((resolve, reject) => {
        const id = String(++seq);
        pending.set(id, { resolve, reject });
        try { window.__qydBridge(JSON.stringify({ id, name, args })); } catch (e) { pending.delete(id); reject(e); }
      });
    },
  };
  window.dispatchEvent(new Event('flutterInAppWebViewPlatformReady'));
})();`;

/** The app's value normalisation (jsArg): text as is, numbers/booleans as text, objects as JSON, nothing as ''. */
export function jsArg(v) {
  if (v == null) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

function q(s) {
  return JSON.stringify(String(s ?? ''));
}

/** The app's SourceParse.decode: JSON text (twice when it holds a JSON string) -> value. */
export function decode(v) {
  let d = v;
  for (let i = 0; i < 2 && typeof d === 'string'; i++) {
    const t = d.trim();
    if (!t) return null;
    try {
      d = JSON.parse(t);
    } catch {
      return i === 0 ? null : d;
    }
  }
  return d;
}

export function decryptAes(data, key) {
  const k = Buffer.from(key, 'utf8');
  const algo = { 16: 'aes-128-cbc', 24: 'aes-192-cbc', 32: 'aes-256-cbc' }[k.length];
  if (!algo) throw new Error('@aes key must be 16, 24 or 32 bytes');
  const d = crypto.createDecipheriv(algo, k, k);
  return Buffer.concat([d.update(Buffer.from(data.trim(), 'base64')), d.final()]).toString('utf8');
}

export class Runner {
  /**
   * opts: page (file or url), base, stateDir, headful, ua, device, aesKey, log(line), quiet, cookies [{url, text}],
   * cacheSeed {k: v}, timeouts {}
   */
  static async start(opts) {
    const r = new Runner(opts);
    await r.#start();
    return r;
  }

  constructor(opts) {
    this.opts = opts;
    this.page = opts.page;
    this.isUrl = /^https?:\/\//i.test(this.page);
    this.base = (opts.base ?? (this.isUrl ? this.page : 'http://localhost/')).trim();
    this.stateDir = opts.stateDir ?? path.join(HERE, '.state', md5(this.base.toLowerCase()));
    this.timeouts = { ...TIMEOUTS, ...(opts.timeouts ?? {}) };
    this.log = opts.log ?? ((s) => process.stderr.write(s + '\n'));
    this.ready = false;
    this.isCookieJar = true;
    this.state = {};
    this.texts = [];
    this.toasts = [];
    this.calls = new Map();
    this.deviceIdFile = path.join(HERE, '.state', 'device.json');
  }

  #deviceId() {
    try {
      const j = JSON.parse(fs.readFileSync(this.deviceIdFile, 'utf8'));
      if (j.id) return j.id;
    } catch {}
    const id = crypto.randomUUID();
    fs.mkdirSync(path.dirname(this.deviceIdFile), { recursive: true });
    fs.writeFileSync(this.deviceIdFile, JSON.stringify({ id }));
    return id;
  }

  async #loadPage() {
    let html = '';
    if (!this.isUrl) {
      html = fs.readFileSync(this.page, 'utf8').trim();
    } else {
      this.log(`获取html ${this.page}`);
      const res = await fetch(this.page, { headers: { 'User-Agent': this.ua, deviceid: this.deviceId } });
      if (!res.ok) throw new Error(`获取在线书源失败: HTTP ${res.status}`);
      html = (await res.text()).trim();
      this.log('完成获取html');
    }
    if (html.startsWith('@aes')) {
      const key = this.opts.aesKey ?? process.env.QREAD_SOURCE_AES_KEY ?? '';
      if (!key) throw new Error('解密失败: 不支持加密书源 (set --aes-key / QREAD_SOURCE_AES_KEY)');
      html = decryptAes(html.slice(4), key);
    }
    return html;
  }

  async #start() {
    const o = this.opts;
    this.ua = o.ua ?? DEFAULT_UA;
    this.deviceId = this.#deviceId();
    this.jar = new CookieJar(path.join(this.stateDir, 'cookies.json'));
    this.cache = new KvCache(path.join(this.stateDir, 'cache.json'));
    this.shared = new KvCache(path.join(HERE, '.state', 'all.json'));
    for (const c of o.cookies ?? []) this.jar.set(c.url, c.text);
    for (const [k, v] of Object.entries(o.cacheSeed ?? {})) this.cache.set(k, v);
    const html = await this.#loadPage();

    this.chrome = await launchChrome({ headless: !o.headful });
    this.cdp = await CDP.connect(this.chrome.wsUrl);
    this.handlers = createHandlers({
      sourceUrl: this.base,
      jar: this.jar,
      cache: this.cache,
      shared: this.shared,
      ua: this.ua,
      device: o.device ?? 'ios',
      deviceId: this.deviceId,
      state: this.state,
      log: o.quiet ? () => {} : (s) => this.log(`  ${s}`),
      text: (type, h) => {
        this.texts.push({ type, html: h });
        if (!o.quiet) this.log(`  text(${type}): ${h.length} chars`);
      },
      toast: (m) => {
        this.toasts.push(m);
        this.log(`  弹窗: ${m}`);
      },
      onReady: (flag) => {
        this.isCookieJar = flag;
        this.ready = true;
      },
      onCall: (id, v) => {
        const c = this.calls.get(id);
        if (c) {
          this.calls.delete(id);
          c(v);
        }
      },
      webview: (req) => this.webview(req),
      browser: (req) => this.browser(req),
    });
    this.handlers.http = ((orig) => (a) => orig(a))(this.handlers.http);
    this.session = await this.#preparePage(html);
  }

  /** A page target with the bridge installed; `html` (when given) is served for the base url. */
  async #preparePage(html) {
    const s = await newPage(this.cdp);
    await s.send('Page.enable');
    await s.send('Runtime.enable');
    await s.send('Network.enable');
    await s.send('Network.setUserAgentOverride', { userAgent: this.ua });
    await s.send('Runtime.addBinding', { name: '__qydBridge' });
    await s.send('Page.addScriptToEvaluateOnNewDocument', { source: SHIM });
    s.on('Runtime.bindingCalled', (p) => this.#onBinding(s, p));
    s.on('Runtime.consoleAPICalled', (p) => {
      if (this.opts.quiet) return;
      const text = p.args.map((a) => (a.value !== undefined ? (typeof a.value === 'string' ? a.value : JSON.stringify(a.value)) : a.description ?? a.type)).join(' ');
      this.log(`  console.${p.type}: ${text.slice(0, 500)}`);
    });
    s.on('Runtime.exceptionThrown', (p) => this.log(`  page error: ${p.exceptionDetails.exception?.description ?? p.exceptionDetails.text}`));
    if (html !== undefined && html !== null && !this.isUrl) {
      await s.send('Fetch.enable', { patterns: [{ urlPattern: this.base, requestStage: 'Request' }] });
      s.on('Fetch.requestPaused', async (p) => {
        try {
          if (p.request.url === this.base || p.request.url === this.base.replace(/\/$/, '') || p.request.url.replace(/\/$/, '') === this.base.replace(/\/$/, '')) {
            await s.send('Fetch.fulfillRequest', { requestId: p.requestId, responseCode: 200, responseHeaders: [{ name: 'Content-Type', value: 'text/html; charset=utf-8' }], body: Buffer.from(html, 'utf8').toString('base64') });
          } else await s.send('Fetch.continueRequest', { requestId: p.requestId });
        } catch (e) {
          this.log(`  fetch intercept: ${e.message}`);
        }
      });
    }
    const target = this.isUrl ? this.page : this.base;
    await s.send('Page.navigate', { url: target });
    return s;
  }

  async #onBinding(session, p) {
    if (p.name !== '__qydBridge') return;
    let msg;
    try {
      msg = JSON.parse(p.payload);
    } catch {
      return;
    }
    const { id, name, args = [] } = msg;
    let ok = true;
    let value = null;
    const h = this.handlers[name];
    if (!h) {
      ok = false;
      value = `no handler: ${name}`;
      this.log(`  !! unknown handler ${name}(${args.map((a) => JSON.stringify(a)).join(', ').slice(0, 200)})`);
    } else {
      try {
        value = await h(args);
        if (value === undefined) value = null;
      } catch (e) {
        ok = false;
        value = String(e?.message ?? e);
        this.log(`  handler ${name} failed: ${value}`);
      }
    }
    if (this.closed) return;
    try {
      await session.send('Runtime.evaluate', { expression: `window.__qydResolve(${JSON.stringify(String(id))}, ${ok}, ${JSON.stringify(value)})` });
    } catch (e) {
      if (!this.closed) this.log(`  resolve ${name}: ${e.message}`);
    }
  }

  /** 0xe097d8: waits for the page's CookieJar call. */
  async waitReady() {
    const deadline = Date.now() + this.timeouts.ready;
    while (!this.ready) {
      if (Date.now() > deadline) throw new Error('等待页面就绪超时');
      await new Promise((r) => setTimeout(r, 10));
    }
  }

  /** Runs `expr` (a call of a page function) and answers its value normalised like the app. */
  async call(expr, timeoutMs) {
    if (!this.ready) {
      this.log('等待书源 html 加载完成');
      await this.waitReady();
      this.log('书源已加载完成');
    }
    const wrapped = `(async () => { try { const r = await (${expr}); return { ok: true, v: r === undefined ? null : r }; } catch (e) { return { ok: false, e: String((e && e.stack) || e) }; } })()`;
    const t0 = Date.now();
    const res = await withTimeout(this.session.evaluate(wrapped), timeoutMs ?? 120000, `等待函数执行超时 (${expr.slice(0, 60)})`);
    this.lastMs = Date.now() - t0;
    if (!res || res.ok === false) {
      this.log(`  ${expr.slice(0, 80)}: ${res?.e ?? 'no result'}`);
      return '';
    }
    return jsArg(res.v);
  }

  search(key, page = 1, env = 'search') {
    return this.call(`search(${q(key)},${Number(page) || 1},${q(env)})`, this.timeouts.search);
  }

  info(bookUrl) {
    return this.call(`info(${q(bookUrl)})`, this.timeouts.info);
  }

  chapter(tocUrl, bookUrl = '') {
    return this.call(`chapter(${q(tocUrl)},${q(bookUrl)})`, this.timeouts.chapter);
  }

  content(url, bookUrl = '', index = 0) {
    return this.call(`content(${q(url)},${q(bookUrl)},${Number(index) || 0})`, this.timeouts.content);
  }

  getfinds() {
    return this.call('getfinds()', this.timeouts.finds);
  }

  find(url, page = 1) {
    return this.call(`find(${q(url)},${Number(page) || 1})`, this.timeouts.find);
  }

  getloginurl() {
    return this.call('getloginurl()', this.timeouts.login);
  }

  login() {
    return this.call('login()', this.timeouts.login);
  }

  pay(bookUrl, url) {
    return this.call(`pay(${q(bookUrl)},${q(url)})`, this.timeouts.pay);
  }

  gethelp() {
    return this.call('gethelp()', this.timeouts.help);
  }

  filter() {
    return this.call('filter()', this.timeouts.find);
  }

  findfilter(url) {
    return this.call(`findfilter(${q(url)})`, this.timeouts.find);
  }

  callbackjs(event, bookJson = '{}') {
    return this.call(`callbackjs(${q(event)},${q(bookJson)})`, this.timeouts.find);
  }

  shouldOverrideUrlLoading(url) {
    return this.call(`shouldOverrideUrlLoading(${q(url)})`, 30000);
  }

  /** An explore entry's `action` (the app evals the text in the page). */
  runJs(code) {
    return this.call(`(async function(){ return await eval(${q(code)}); })()`, this.timeouts.find);
  }

  /** The page's `webview` handler: a background page that answers html / a js value / a matching url. */
  async webview(req) {
    const s = await newPage(this.cdp);
    const log = (m) => this.opts.quiet || this.log(`  webview: ${m}`);
    let settled = false;
    let answer;
    const finish = (v) => {
      if (!settled) {
        settled = true;
        answer = v;
      }
    };
    try {
      await s.send('Page.enable');
      await s.send('Runtime.enable');
      await s.send('Network.enable');
      await s.send('Network.setUserAgentOverride', { userAgent: req.headers?.['User-Agent'] ?? req.headers?.['user-agent'] ?? this.ua });
      const extra = { ...(req.headers ?? {}) };
      delete extra['User-Agent'];
      delete extra['user-agent'];
      if (Object.keys(extra).length) await s.send('Network.setExtraHTTPHeaders', { headers: extra });
      if (req.url) {
        for (const [name, value] of Object.entries(this.jar.map(req.url))) {
          try {
            await s.send('Network.setCookie', { name, value, url: req.url });
          } catch {}
        }
      }
      const matched = [];
      const reUrl = req.urlregex ? new RegExp(req.urlregex) : null;
      const reOverride = req.overrideUrlRegex ? new RegExp(req.overrideUrlRegex) : null;
      const reAjax = req.ajaxregex ? new RegExp(req.ajaxregex) : null;
      s.on('Network.requestWillBeSent', (p) => {
        const u = p.request.url;
        if (reUrl && reUrl.test(u)) matched.push(u);
        if (reOverride && p.type === 'Document' && reOverride.test(u)) matched.push(u);
      });
      if (reAjax) {
        s.on('Network.loadingFinished', async (p) => {
          const r = ajaxUrls.get(p.requestId);
          if (!r) return;
          try {
            const body = await s.send('Network.getResponseBody', { requestId: p.requestId });
            matched.push(body.base64Encoded ? Buffer.from(body.body, 'base64').toString('utf8') : body.body);
          } catch {}
        });
      }
      const ajaxUrls = new Map();
      s.on('Network.responseReceived', (p) => {
        if (reAjax && (p.type === 'XHR' || p.type === 'Fetch') && reAjax.test(p.response.url)) ajaxUrls.set(p.requestId, p.response.url);
      });
      if (req.html || req.body) {
        const target = req.url || 'http://localhost/';
        await s.send('Fetch.enable', { patterns: [{ urlPattern: target, requestStage: 'Request' }] });
        s.on('Fetch.requestPaused', async (p) => {
          try {
            if (req.html && p.request.url.replace(/\/$/, '') === target.replace(/\/$/, '')) {
              await s.send('Fetch.fulfillRequest', { requestId: p.requestId, responseCode: 200, responseHeaders: [{ name: 'Content-Type', value: 'text/html; charset=utf-8' }], body: Buffer.from(req.html, 'utf8').toString('base64') });
            } else if (req.body && p.request.method === 'GET' && p.request.url.replace(/\/$/, '') === target.replace(/\/$/, '')) {
              const headers = Object.entries({ ...p.request.headers, ...(req.headers ?? {}) }).map(([name, value]) => ({ name, value: String(value) }));
              await s.send('Fetch.continueRequest', { requestId: p.requestId, method: 'POST', postData: Buffer.from(req.body, 'utf8').toString('base64'), headers });
            } else await s.send('Fetch.continueRequest', { requestId: p.requestId });
          } catch (e) {
            log(`intercept: ${e.message}`);
          }
        });
      }
      const loaded = s.waitFor('Page.loadEventFired', { timeoutMs: 60000 }).catch(() => null);
      await s.send('Page.navigate', { url: req.url || 'http://localhost/' });
      const started = Date.now();
      // a match answers 1 s later (the app's waittime); else the page once quiet (1 s after load), 60 s at most
      while (Date.now() - started < 60000) {
        if (matched.length) {
          await new Promise((r) => setTimeout(r, reAjax ? 2000 : 1000));
          finish(matched[0]);
          break;
        }
        const l = await Promise.race([loaded, new Promise((r) => setTimeout(() => r('pending'), 250))]);
        if (l !== 'pending') {
          await new Promise((r) => setTimeout(r, 1000));
          if (matched.length) {
            finish(matched[0]);
            break;
          }
          finish(undefined);
          break;
        }
      }
      if (answer === undefined) {
        try {
          answer = jsArg(await s.evaluate(req.js?.trim() ? req.js : 'document.documentElement.outerHTML', { timeoutMs: 30000 }));
        } catch (e) {
          log(`js failed: ${e.message}`);
          answer = '';
        }
      }
      if (req.url) {
        try {
          const { cookies } = await s.send('Network.getCookies', { urls: [req.url] });
          for (const c of cookies) this.jar.setOne(req.url, c.name, c.value);
        } catch {}
      }
      log(`${req.url || '(html)'} -> ${String(answer).length} chars`);
      return answer ?? '';
    } finally {
      await closePage(this.cdp, s);
    }
  }

  /** The page's `startBrowser*` handlers: no user here, the page html after it loaded is the answer. */
  async browser(req) {
    this.log(`  startBrowser: ${req.url} (${req.title}) — no user interaction in the runner; answering the loaded page`);
    this.state.browser = [...(this.state.browser ?? []), req.url];
    if (req.override) {
      try {
        const v = await this.shouldOverrideUrlLoading(req.url);
        this.log(`  shouldOverrideUrlLoading(${req.url}) -> ${v}`);
        if (v === 'false') return '';
      } catch {}
    }
    return this.webview({ url: req.url, headers: req.headers ?? {} });
  }

  async close() {
    this.closed = true;
    try {
      this.cdp?.close();
    } catch {}
    this.chrome?.kill();
  }
}

// ---------------------------------------------------------------- CLI

function parseArgs(argv) {
  const o = { cookies: [], cacheSeed: {} };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '--page': o.page = next(); break;
      case '--base': o.base = next(); break;
      case '--state': o.stateDir = path.resolve(next()); break;
      case '--cookie': o.cookies.push({ url: next(), text: next() }); break;
      case '--cache': { const k = next(); o.cacheSeed[k] = next(); break; }
      case '--aes-key': o.aesKey = next(); break;
      case '--timeout': o.timeout = Number(next()) * 1000; break;
      case '--headful': o.headful = true; break;
      case '--device': o.device = next(); break;
      case '--ua': o.ua = next(); break;
      case '--json': o.json = true; break;
      case '--quiet': o.quiet = true; break;
      case '--help': case '-h': o.help = true; break;
      default: rest.push(a);
    }
  }
  if (o.timeout) o.timeouts = Object.fromEntries(Object.keys(TIMEOUTS).map((k) => [k, o.timeout]));
  return { o, rest };
}

function summarize(kind, value, log) {
  const d = decode(value);
  if (kind === 'books') {
    if (!Array.isArray(d)) return log(`  -> not a book list (${value.slice(0, 120)})`);
    log(`  -> ${d.length} books`);
    d.slice(0, 5).forEach((b, i) => log(`     ${i}. ${b.name} / ${b.author} [${b.kind ?? ''}] ${b.latestChapterTitle ?? ''}\n        bookUrl=${b.bookUrl}`));
  } else if (kind === 'book') {
    if (!d || typeof d !== 'object') return log(`  -> not a book (${value.slice(0, 120)})`);
    log(`  -> ${d.name} / ${d.author} type=${d.type} words=${d.wordCount} cover=${d.coverUrl}\n     tocUrl=${d.tocUrl}\n     intro=${String(d.intro ?? '').replace(/\s+/g, ' ').slice(0, 160)}`);
  } else if (kind === 'chapters') {
    if (!Array.isArray(d)) return log(`  -> not a chapter list (${value.slice(0, 120)})`);
    log(`  -> ${d.length} chapters; first: ${d[0]?.name} (${String(d[0]?.chapterId).slice(0, 80)}); last: ${d[d.length - 1]?.name}`);
  } else if (kind === 'finds') {
    if (!Array.isArray(d)) return log(`  -> not an explore list (${value.slice(0, 120)})`);
    log(`  -> ${d.length} explore entries`);
    d.slice(0, 12).forEach((k) => log(`     ${k.type ?? 0} ${k.title} ${k.url ?? ''} ${k.chars ? `[${k.chars.length} choices, default ${k.default}]` : ''}`));
  } else if (kind === 'text') {
    log(`  -> ${value.length} chars: ${value.replace(/\s+/g, ' ').slice(0, 300)}`);
  }
}

async function main() {
  const { o, rest } = parseArgs(process.argv.slice(2));
  const [cmd, ...args] = rest;
  if (o.help || !cmd || !o.page) {
    const src = fs.readFileSync(fileURLToPath(import.meta.url), 'utf8');
    process.stdout.write(src.split('\n').slice(1, 26).map((l) => l.replace(/^\/\/ ?/, '')).join('\n') + '\n');
    process.exit(cmd && !o.page ? 2 : 0);
  }
  const log = (s) => process.stderr.write(s + '\n');
  const r = await Runner.start({ ...o, log });
  const out = (kind, value) => {
    if (!o.json) summarize(kind, value, log);
    process.stdout.write(value + '\n');
  };
  try {
    log(`page ${r.page} base ${r.base} state ${r.stateDir}`);
    switch (cmd) {
      case 'ready': await r.waitReady(); log(`ready, isCookieJar=${r.isCookieJar}`); break;
      case 'finds': out('finds', await r.getfinds()); break;
      case 'find': out('books', await r.find(args[0], args[1] ?? 1)); break;
      case 'search': out('books', await r.search(args[0], args[1] ?? 1, args[2] ?? 'search')); break;
      case 'info': out('book', await r.info(args[0])); break;
      case 'chapter': out('chapters', await r.chapter(args[0], args[1] ?? '')); break;
      case 'content': out('text', await r.content(args[0], args[1] ?? '', args[2] ?? 0)); break;
      case 'help': out('text', await r.gethelp()); break;
      case 'loginurl': out('text', await r.getloginurl()); break;
      case 'login': out('text', await r.login()); break;
      case 'filter': out('text', await r.filter()); break;
      case 'findfilter': out('text', await r.findfilter(args[0])); break;
      case 'pay': out('text', await r.pay(args[0], args[1])); break;
      case 'event': out('text', await r.callbackjs(args[0], args[1] ?? '{}')); break;
      case 'action': out('text', await r.runJs(args[0])); break;
      case 'js': out('text', await r.call(args[0], o.timeout ?? 120000)); break;
      case 'flow': {
        const n = Number(args[1] ?? 0);
        const ci = Number(args[2] ?? 0);
        log(`︾ search ${args[0]}`);
        const books = decode(await r.search(args[0], 1));
        if (!Array.isArray(books) || !books[n]) throw new Error('no search result');
        summarize('books', JSON.stringify(books), log);
        const b = books[n];
        log(`︾ info ${b.bookUrl} (${r.lastMs} ms)`);
        const info = decode(await r.info(b.bookUrl));
        summarize('book', JSON.stringify(info), log);
        const tocUrl = info?.tocUrl || b.tocUrl || b.bookUrl;
        log(`︾ chapter ${tocUrl.slice(0, 100)} (${r.lastMs} ms)`);
        const chapters = decode(await r.chapter(tocUrl, b.bookUrl));
        summarize('chapters', JSON.stringify(chapters), log);
        const c = Array.isArray(chapters) ? chapters[ci] : null;
        if (!c) throw new Error('no chapters');
        log(`︾ content ${c.name} (${r.lastMs} ms)`);
        const text = await r.content(c.chapterId ?? c.url, b.bookUrl, ci);
        summarize('text', text, log);
        log(`︽ done (${r.lastMs} ms); toasts: ${r.toasts.length}, texts: ${r.texts.length}`);
        process.stdout.write(JSON.stringify({ book: info ?? b, chapters: chapters.length, chapter: c, content: text }) + '\n');
        break;
      }
      default: throw new Error(`unknown command ${cmd}`);
    }
  } catch (e) {
    log(`error: ${e.message ?? e}`);
    process.exitCode = 1;
  } finally {
    await r.close();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
