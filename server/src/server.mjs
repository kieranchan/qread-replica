// HTTP entry point. Routes:
//   <endpoint>              account / cloud API (userapi.mjs), GET or POST, JSON / form / multipart bodies
//   /vip, /vip.js           会员中心 page          /redeem  activation-code redemption (used by the page)
//   /public/themes[/:id], /public/categories, /public/files/*   theme plaza
//   /images/*, /static/down.json, /static/qq.json, /static/browser.html, /tsy/<name>.html (hosted 时光源 pages), /healthz, /api/allocate (stub)
//   PUT|GET /autobackup/<key>   upload / download of a device backup (urls handed out by openAuto / newopenAuto2 / getBookSelf ...)
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { openDb } from './db.mjs';
import { Service } from './service.mjs';
import { createAutoBackups, createUserApi } from './userapi.mjs';
import { createThemes } from './themes.mjs';
import { createLuis } from './luis/api.mjs';
import { createDav } from './dav.mjs';
import { VIP_HTML, VIP_JS } from './pages.mjs';
import { ApiError, CODE, RateLimiter, readBody, parseMultipart } from './util.mjs';

const SAFE_NAME = /^[A-Za-z0-9._\-]{1,128}$/;
const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.zip': 'application/zip', '.json': 'application/json; charset=utf-8', '.html': 'text/html; charset=utf-8' };

export function createApp(overrides = {}) {
  const cfg = loadConfig(overrides);
  const db = openDb(cfg.dbPath);
  const svc = new Service(db, cfg);
  const limiter = new RateLimiter();
  const api = createUserApi(svc, cfg, limiter);
  const autoBackups = createAutoBackups(svc);
  const dav = createDav(svc, cfg, { readBody });
  const themes = createThemes(db);
  // 路易斯 aggregation platform under /luis (overrides.luisAdapters: an adapter list, or db => list, for tests)
  const luis = createLuis({ db, cfg, svc, limiter, adapters: typeof overrides.luisAdapters === 'function' ? overrides.luisAdapters(db) : overrides.luisAdapters });
  const startedAt = Date.now();

  function clientIp(req) {
    const remote = req.socket.remoteAddress ?? '';
    const loopback = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
    if (cfg.trustProxy && loopback) {
      const h = req.headers['cf-connecting-ip'] ?? req.headers['x-forwarded-for'];
      if (h) return String(h).split(',')[0].trim();
    }
    return remote;
  }

  function send(res, status, body, headers = {}) {
    const isStr = typeof body === 'string' || Buffer.isBuffer(body);
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      ...headers,
    });
    res.end(isStr ? body : JSON.stringify(body));
  }

  function sendFile(res, dir, name, cache) {
    if (!SAFE_NAME.test(name)) return send(res, 404, { code: 404, message: 'not found' });
    const p = path.join(dir, name);
    let st;
    try {
      st = fs.statSync(p);
    } catch {
      return send(res, 404, { code: 404, message: 'not found' });
    }
    if (!st.isFile()) return send(res, 404, { code: 404, message: 'not found' });
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(name).toLowerCase()] ?? 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': cache,
      'X-Content-Type-Options': 'nosniff',
    });
    fs.createReadStream(p).pipe(res);
  }

  async function handle(req, res) {
    const t0 = Date.now();
    const url = new URL(req.url, 'http://x');
    const pathname = url.pathname.replace(/\/+$/, '') || '/';
    const ip = clientIp(req);
    let status = 200;
    try {
      if (pathname === '/luis' || pathname.startsWith('/luis/')) {
        status = await luis.handle(req, res, url, pathname, ip);
        return;
      }
      // WebDAV book repository of the app's 云端仓库 (dav.mjs): Basic auth, per-user folder
      if (pathname === '/dav' || pathname.startsWith('/dav/')) {
        status = await dav.handle(req, res, url, pathname);
        return;
      }
      // ---- static / pages ----
      if (req.method === 'GET' || req.method === 'HEAD') {
        if (pathname === '/healthz') return send(res, 200, { ok: true, users: db.prepare('SELECT COUNT(*) AS n FROM users').get().n, uptime: Math.round((Date.now() - startedAt) / 1000) });
        if (pathname === '/vip' || pathname === '/') {
          return send(res, 200, VIP_HTML, { 'Content-Type': 'text/html; charset=utf-8', 'Referrer-Policy': 'no-referrer',
            'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'" });
        }
        if (pathname === '/vip.js') return send(res, 200, VIP_JS, { 'Content-Type': 'application/javascript; charset=utf-8' });
        if (pathname === '/public/categories') return send(res, 200, themes.categories());
        if (pathname === '/public/themes') {
          return send(res, 200, themes.list(Object.fromEntries(url.searchParams)));
        }
        if (pathname.startsWith('/public/themes/')) return send(res, 200, themes.get(decodeURIComponent(pathname.slice('/public/themes/'.length))));
        if (pathname.startsWith('/public/files/')) return sendFile(res, path.join(cfg.dataDir, 'themes', 'files'), pathname.slice('/public/files/'.length), 'public, max-age=86400');
        if (pathname.startsWith('/images/')) return sendFile(res, path.join(cfg.dataDir, 'images'), pathname.slice('/images/'.length), 'public, max-age=31536000, immutable');
        if (pathname === '/static/down.json' || pathname === '/static/qq.json') {
          const f = path.join(cfg.dataDir, 'static', path.basename(pathname));
          return send(res, 200, fs.existsSync(f) ? fs.readFileSync(f) : '{}');
        }
        if (pathname.startsWith('/tsy/')) {
          // hosted 时光源 pages (`qread-admin set-source <name> <file.html>`, sources/ of the repository): a source whose record has
          // `html: <base>/tsy/<name>.html` downloads the page on every start, so it is updated without re-importing
          return sendFile(res, path.join(cfg.dataDir, 'static', 'tsy'), `${pathname.slice('/tsy/'.length).replace(/\.html$/, '')}.html`, 'public, max-age=300');
        }
        if (pathname === '/static/browser.html') {
          // the 「浏览器」 时光源 page of the app's 阅读模式 (`qread-admin set-static browser <file.html>`); 404 = the app uses its built-in page
          const f = path.join(cfg.dataDir, 'static', 'browser.html');
          if (!fs.existsSync(f)) { status = 404; return send(res, 404, { code: CODE.ERR, errorMsg: 'not found' }); }
          return send(res, 200, fs.readFileSync(f), { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' });
        }
      }
      if (pathname === '/api/allocate') return send(res, 200, { code: -1, msg: '兼容层服务未启用' });
      if (pathname.startsWith('/autobackup/')) {
        const key = pathname.slice('/autobackup/'.length);
        if (req.method === 'PUT' || req.method === 'POST') {
          const buf = await readBody(req, cfg.maxBodyBytes);
          if (!autoBackups.put(key, buf, Date.now())) {
            status = 404;
            return send(res, 404, { code: CODE.ERR, errorMsg: 'not found' });
          }
          return send(res, 200, { code: 0 });
        }
        if (req.method === 'GET' || req.method === 'HEAD') {
          const data = autoBackups.get(key);
          if (!data) {
            status = 404;
            return send(res, 404, { code: 404, message: 'not found' });
          }
          return send(res, 200, data);
        }
        status = 405;
        return send(res, 405, { code: CODE.ERR, errorMsg: 'method not allowed' });
      }

      // ---- account / cloud API ----
      const name = pathname.slice(1);
      if (!name || name.includes('/') || !Object.hasOwn(api, name)) {
        status = 404;
        if (cfg.log && name) console.warn(JSON.stringify({ unsupported: name, method: req.method, ip }));
        return send(res, 404, { code: CODE.ERR, errorMsg: 'unsupported endpoint' }, {});
      }
      let fields = {};
      let files = {};
      if (req.method === 'POST' || req.method === 'PUT') {
        const buf = await readBody(req, cfg.maxBodyBytes);
        const ct = String(req.headers['content-type'] ?? '');
        if (ct.includes('multipart/form-data')) ({ fields, files } = parseMultipart(buf, ct));
        else if (ct.includes('application/x-www-form-urlencoded')) fields = Object.fromEntries(new URLSearchParams(buf.toString('utf8')));
        else if (buf.length) {
          try {
            const j = JSON.parse(buf.toString('utf8'));
            if (j && typeof j === 'object' && !Array.isArray(j)) fields = j;
          } catch {
            throw new ApiError(CODE.ERR, '请求格式错误', 400);
          }
        }
      }
      const p = { ...Object.fromEntries(url.searchParams), ...fields };
      if (!p.tockenid && req.headers['x-tockenid']) p.tockenid = String(req.headers['x-tockenid']);
      const out = await api[name]({ p, files, ip, now: Date.now(), method: req.method });
      return send(res, 200, out);
    } catch (e) {
      if (e instanceof ApiError) {
        status = e.status;
        return send(res, e.status, { code: e.code, errorMsg: e.msg });
      }
      status = 500;
      console.error(JSON.stringify({ error: String(e?.stack ?? e), path: pathname }));
      return send(res, 500, { code: CODE.ERR, errorMsg: 'server error' });
    } finally {
      if (cfg.log) console.log(JSON.stringify({ ip, m: req.method, p: pathname, s: status, ms: Date.now() - t0 }));
    }
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((e) => {
      console.error(String(e?.stack ?? e));
      if (!res.headersSent) res.writeHead(500);
      res.end();
    });
  });
  server.requestTimeout = 60_000;
  server.headersTimeout = 20_000;
  server.keepAliveTimeout = 5_000;
  return { server, svc, db, cfg, luis, close: () => new Promise((r) => server.close(() => { db.close(); r(); })) };
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
if (isMain) {
  const app = createApp();
  app.server.listen(app.cfg.port, app.cfg.host, () => {
    console.log(JSON.stringify({ listening: `${app.cfg.host}:${app.cfg.port}`, data: app.cfg.dataDir, baseUrl: app.cfg.baseUrl, register: app.cfg.register }));
  });
  const stop = () => app.close().then(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
