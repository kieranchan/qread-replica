// HTTP surface of 路易斯 under /luis: the aggregation calls of the 时光源 page (same paths and reply shapes as the
// 大灰狼 backend), the login page that sets the `qttoken` / `deviceId` cookies the page relies on, and the user centre.
import crypto from 'node:crypto';
import os from 'node:os';
import { ApiError, CODE, readBody, fmtDate } from '../util.mjs';
import { LuisEngine } from './engine.mjs';
import { wikisourceAdapter } from './adapters/wikisource.mjs';
import { libraryAdapter } from './adapters/library.mjs';
import { LOGIN_HTML, USER_HTML, APP_JS } from './pages.mjs';

const MIN = 60_000;
const YEAR = 365 * 24 * 3600;

export function defaultAdapters(db) {
  return [wikisourceAdapter(), libraryAdapter(db)];
}

function parseCookies(req) {
  const out = {};
  for (const part of String(req.headers.cookie ?? '').split(';')) {
    const i = part.indexOf('=');
    if (i <= 0) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

function cookie(name, value, { maxAge = YEAR, secure = false, httpOnly = true } = {}) {
  return `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${maxAge}; SameSite=Lax${secure ? '; Secure' : ''}${httpOnly ? '; HttpOnly' : ''}`;
}

const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };

function sendJson(res, status, body, extra = {}) {
  res.writeHead(status, { ...JSON_HEADERS, ...extra });
  res.end(JSON.stringify(body));
  return status;
}

function sendHtml(res, body) {
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'",
  });
  res.end(body);
  return 200;
}

function redirect(res, to) {
  res.writeHead(302, { Location: to, 'Cache-Control': 'no-store' });
  res.end();
  return 302;
}

async function bodyFields(req, limit) {
  if (req.method !== 'POST') return {};
  const buf = await readBody(req, limit);
  const ct = String(req.headers['content-type'] ?? '');
  if (ct.includes('application/x-www-form-urlencoded')) return Object.fromEntries(new URLSearchParams(buf.toString('utf8')));
  if (!buf.length) return {};
  try {
    const j = JSON.parse(buf.toString('utf8'));
    return j && typeof j === 'object' && !Array.isArray(j) ? j : {};
  } catch {
    throw new ApiError(CODE.ERR, '请求格式错误', 400);
  }
}

export function createLuis({ db, cfg, svc, limiter, adapters }) {
  const engine = new LuisEngine({ db, cfg, svc, adapters: adapters ?? defaultAdapters(db) });
  const secure = cfg.baseUrl.startsWith('https://');

  function userOf(req, url, c) {
    const token = c.qttoken || url.searchParams.get('qttoken') || String(req.headers['x-tockenid'] ?? '');
    if (!token) return { user: null, token: '' };
    try {
      return { user: svc.authenticate(token).user, token };
    } catch {
      return { user: null, token: '' };
    }
  }

  function vipText(user, now) {
    if (!svc.isVip(user, now)) return '';
    return user.vip_until - now > 50 * 365 * 24 * 3600_000 ? '永久' : fmtDate(user.vip_until);
  }

  /** Handles one request under /luis; answers the HTTP status it sent. */
  async function handle(req, res, url, pathname, ip) {
    const p = pathname === '/luis' ? '/' : pathname.slice('/luis'.length);
    const q = Object.fromEntries(url.searchParams);
    const now = Date.now();
    try {
      if (!limiter.allow(`luis:${ip}`, 240, MIN, now)) throw new ApiError(CODE.ERR, '请求过于频繁，请稍后再试');
      const c = parseCookies(req);
      const { user, token } = userOf(req, url, c);
      switch (p) {
        case '/':
          return redirect(res, '/luis/user');
        case '/login':
          if (req.method === 'GET' || req.method === 'HEAD') return sendHtml(res, LOGIN_HTML);
          break;
        case '/user':
          return sendHtml(res, USER_HTML);
        case '/app.js':
          res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8', 'Cache-Control': 'no-store' });
          res.end(APP_JS);
          return 200;
        case '/login_api': {
          if (req.method !== 'POST') throw new ApiError(CODE.ERR, 'POST only', 405);
          const f = await bodyFields(req, cfg.maxBodyBytes);
          const username = String(f.username ?? '').trim();
          const k1 = `login:${ip}:${username.toLowerCase()}`;
          const k2 = `login-ip:${ip}`;
          if (limiter.blocked(k1, 8, 10 * MIN, now) || limiter.blocked(k2, 40, 10 * MIN, now)) throw new ApiError(CODE.ERR, '尝试次数过多，请稍后再试');
          const u = svc.findUser(username);
          if (!svc.checkPassword(u, f.password)) {
            limiter.fail(k1, now);
            limiter.fail(k2, now);
            throw new ApiError(CODE.ERR, '用户名或密码错误');
          }
          limiter.reset(k1);
          const deviceId = /^[A-Za-z0-9_-]{8,64}$/.test(c.deviceId ?? '') ? c.deviceId : crypto.randomBytes(9).toString('base64url');
          const t = svc.issueToken(u, { appid: `luis:${deviceId}`, platform: 'luis', model: String(f.client ?? q.source_client ?? 'web').slice(0, 32) }, now);
          return sendJson(res, 200, { code: 0, data: { username: u.username, nickname: u.nickname, isvip: svc.isVip(u, now), vip: vipText(u, now), next: String(f.next ?? q.next ?? '/luis/user') } }, {
            'Set-Cookie': [cookie('qttoken', t, { secure }), cookie('deviceId', deviceId, { secure, httpOnly: false })],
          });
        }
        case '/logout': {
          if (token) svc.revokeToken(token);
          const clear = [cookie('qttoken', '', { maxAge: 0, secure })];
          if (req.method === 'POST') return sendJson(res, 200, { code: 0 }, { 'Set-Cookie': clear });
          res.writeHead(302, { Location: '/luis/login', 'Set-Cookie': clear, 'Cache-Control': 'no-store' });
          res.end();
          return 302;
        }
        case '/user_api': {
          if (!user) return sendJson(res, 200, { code: CODE.NEED_LOGIN, msg: '未登录' });
          const sc = engine.sourcesConfig();
          const tier = engine.tierOf(user);
          return sendJson(res, 200, {
            code: 0,
            data: {
              username: user.username,
              nickname: user.nickname,
              email: user.email,
              isvip: svc.isVip(user, now),
              vip: vipText(user, now),
              vip_until: fmtDate(user.vip_until),
              registered: fmtDate(user.created_at),
              tier,
              qttoken: token,
              deviceId: c.deviceId ?? '',
              server: engine.base,
              stats: engine.stats(user),
              sources: ['free', 'vip', 'svip'].flatMap((t) => sc[t].map((name) => ({ name, tier: t, tabs: sc.modes[name], available: engine.allowed(engine.adapters.get(name), user) }))),
              page_url: `${cfg.baseUrl}/tsy/luis.html`,
            },
          });
        }
        case '/get_avatar':
          if (!user) return sendJson(res, 400, { code: CODE.NEED_LOGIN, msg: '未登录' });
          return sendJson(res, 200, { code: 0, email: user.email, nickname: user.nickname, avatar: '' });
        case '/api/system_info':
          return sendJson(res, 200, { cpu: os.loadavg()[0], memory: Math.round((1 - os.freemem() / os.totalmem()) * 1000) / 10, uptime: Math.round(process.uptime()) });
        case '/sources/config':
          return sendJson(res, 200, { code: 0, msg: 'Success', data: engine.sourcesConfig() });
        case '/search':
          return sendJson(res, 200, await engine.search({ key: q.title ?? q.key ?? q.q, page: q.page, source: q.source, tab: q.tab || '小说', user }));
        case '/detail':
          return sendJson(res, 200, await engine.detail({ bookId: q.book_id, source: q.source, tab: q.tab || '小说', user }));
        case '/catalog':
          return sendJson(res, 200, await engine.catalog({ bookId: q.book_id, source: q.source, tab: q.tab || '小说', user }));
        case '/content':
          return sendJson(res, 200, await engine.content({ itemId: q.item_id, source: q.source, tab: q.tab || '小说', user }));
        case '/discovestyle':
          return sendJson(res, 200, await engine.discover({ source: q.source, tab: q.tab || '小说', gender: q.source_type || q.gender || '男频', user }));
        case '/get_discover':
          return sendJson(res, 200, await engine.discoverList({ source: q.source, tab: q.tab || '小说', bdtype: q.bdtype, gender: q.gender || '男频', page: q.page, user }));
        default:
          break;
      }
      return sendJson(res, 404, { code: CODE.ERR, msg: 'not found' });
    } catch (e) {
      if (e instanceof ApiError) return sendJson(res, e.status === 200 ? 200 : e.status, { code: e.code, msg: e.msg });
      console.error(JSON.stringify({ luis_error: String(e?.stack ?? e), path: pathname }));
      return sendJson(res, 500, { code: CODE.ERR, msg: 'server error' });
    }
  }

  return { engine, handle };
}
