// dav.mjs — a small WebDAV store per user under `/dav/…`, the book repository behind the app's 云端仓库 (the original app expected the
// user to bring their own WebDAV server; the owner's server offers one so the app can configure it by itself).
//
//   auth      HTTP Basic: username (or e-mail) + the account password, or + a live session token (the app uses its `tockenid`,
//             so no password is ever typed into the network-drive entry)
//   storage   <dataDir>/dav/<user id>/…  (file names are kept as sent, one directory level or more; `..` and empty parts refused)
//   methods   OPTIONS, PROPFIND (Depth 0 / 1), HEAD, GET, PUT, DELETE, MKCOL, MOVE — what the app's webdav_client needs
//   limits    cfg.davMaxFileBytes per file (default 64 MB), cfg.davQuotaBytes per user (default 2 GB)
import fs from 'node:fs';
import path from 'node:path';

const DAV_HEADERS = { DAV: '1', Allow: 'OPTIONS, PROPFIND, HEAD, GET, PUT, DELETE, MKCOL, MOVE', 'MS-Author-Via': 'DAV' };

const xmlEscape = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]);
const hrefOf = (p) => p.split('/').map(encodeURIComponent).join('/');

function dirSize(dir) {
  let n = 0;
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.isFile()) n += fs.statSync(p).size;
    }
  };
  if (fs.existsSync(dir)) walk(dir);
  return n;
}

export function createDav(svc, cfg, { readBody }) {
  const root = path.join(cfg.dataDir, 'dav');
  const maxFile = cfg.davMaxFileBytes ?? 64 * 1024 * 1024;
  const quota = cfg.davQuotaBytes ?? 2 * 1024 * 1024 * 1024;

  /** The user of a Basic header, or null (password or live token). */
  function authenticate(req, now) {
    const h = req.headers.authorization ?? '';
    if (!/^basic /i.test(h)) return null;
    let decoded;
    try {
      decoded = Buffer.from(h.slice(6).trim(), 'base64').toString('utf8');
    } catch {
      return null;
    }
    const i = decoded.indexOf(':');
    if (i <= 0) return null;
    const name = decoded.slice(0, i);
    const secret = decoded.slice(i + 1);
    const user = svc.findUser(name);
    if (!user || user.disabled) return null;
    if (svc.checkPassword(user, secret)) return user;
    try {
      const a = svc.authenticate(secret, now);
      if (a && a.user && a.user.id === user.id) return user;
    } catch {
      /* not a token */
    }
    return null;
  }

  /** The relative parts of a `/dav/...` url, or null when a part is unsafe. */
  function partsOf(pathname) {
    const rest = pathname.replace(/^\/dav\/?/, '');
    if (rest === '') return [];
    const parts = [];
    for (const raw of rest.split('/')) {
      if (raw === '') continue;
      let p;
      try {
        p = decodeURIComponent(raw);
      } catch {
        return null;
      }
      if (p === '.' || p === '..' || p.includes('/') || p.includes('\\') || p.includes('\0') || p.length > 255) return null;
      parts.push(p);
    }
    return parts;
  }

  function entry(userRoot, parts) {
    const abs = path.join(userRoot, ...parts);
    if (abs !== userRoot && !abs.startsWith(userRoot + path.sep)) return null;
    return abs;
  }

  function propfindXml(baseHref, abs, parts, depth) {
    const items = [];
    const self = fs.statSync(abs);
    const selfHref = '/dav/' + hrefOf(parts.join('/')) + (self.isDirectory() && parts.length ? '/' : '');
    items.push({ href: parts.length ? selfHref : '/dav/', name: parts.length ? parts[parts.length - 1] : 'dav', st: self });
    if (self.isDirectory() && depth !== '0') {
      for (const e of fs.readdirSync(abs, { withFileTypes: true })) {
        if (!e.isFile() && !e.isDirectory()) continue;
        const st = fs.statSync(path.join(abs, e.name));
        items.push({ href: '/dav/' + hrefOf([...parts, e.name].join('/')) + (st.isDirectory() ? '/' : ''), name: e.name, st });
      }
    }
    const body = items
      .map(({ href, name, st }) => {
        const dir = st.isDirectory();
        return `<D:response><D:href>${xmlEscape(baseHref + href)}</D:href><D:propstat><D:prop>` +
          `<D:displayname>${xmlEscape(name)}</D:displayname>` +
          `<D:resourcetype>${dir ? '<D:collection/>' : ''}</D:resourcetype>` +
          (dir ? '' : `<D:getcontentlength>${st.size}</D:getcontentlength><D:getcontenttype>application/octet-stream</D:getcontenttype><D:getetag>"${st.size}-${Math.round(st.mtimeMs)}"</D:getetag>`) +
          `<D:getlastmodified>${new Date(st.mtimeMs).toUTCString()}</D:getlastmodified>` +
          `</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>`;
      })
      .join('');
    return `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">${body}</D:multistatus>`;
  }

  function reply(res, status, body = '', headers = {}) {
    res.writeHead(status, { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...DAV_HEADERS, ...headers });
    res.end(body);
    return status;
  }

  /** Handles one `/dav…` request; returns the status for the access log. */
  async function handle(req, res, url, pathname, now = Date.now()) {
    const method = req.method.toUpperCase();
    if (method === 'OPTIONS') return reply(res, 200, '', { 'Content-Length': '0' });
    const user = authenticate(req, now);
    if (!user) return reply(res, 401, 'unauthorized', { 'WWW-Authenticate': 'Basic realm="qread"', 'Content-Type': 'text/plain' });
    const parts = partsOf(url.pathname);
    if (parts === null) return reply(res, 400, 'bad path', { 'Content-Type': 'text/plain' });
    const userRoot = path.join(root, String(user.id));
    fs.mkdirSync(userRoot, { recursive: true });
    const abs = entry(userRoot, parts);
    if (!abs) return reply(res, 400, 'bad path', { 'Content-Type': 'text/plain' });
    const exists = fs.existsSync(abs);
    const baseHref = ''; // hrefs are absolute paths; the client joins them with its own host

    switch (method) {
      case 'PROPFIND': {
        if (!exists) return reply(res, 404, 'not found', { 'Content-Type': 'text/plain' });
        await readBody(req, 1024 * 1024); // the (ignored) prop request
        const depth = String(req.headers.depth ?? '1');
        const xml = propfindXml(baseHref, abs, parts, depth === '0' ? '0' : '1');
        return reply(res, 207, xml, { 'Content-Type': 'application/xml; charset=utf-8' });
      }
      case 'HEAD':
      case 'GET': {
        if (!exists) return reply(res, 404, 'not found', { 'Content-Type': 'text/plain' });
        const st = fs.statSync(abs);
        if (st.isDirectory()) {
          const names = fs.readdirSync(abs);
          return reply(res, 200, JSON.stringify(names), { 'Content-Type': 'application/json; charset=utf-8' });
        }
        res.writeHead(200, { ...DAV_HEADERS, 'Content-Type': 'application/octet-stream', 'Content-Length': st.size, 'Last-Modified': new Date(st.mtimeMs).toUTCString(), 'Cache-Control': 'no-store' });
        if (method === 'HEAD') {
          res.end();
        } else {
          fs.createReadStream(abs).pipe(res);
        }
        return 200;
      }
      case 'PUT': {
        if (parts.length === 0) return reply(res, 405, 'method not allowed', { 'Content-Type': 'text/plain' });
        const parent = path.dirname(abs);
        if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) return reply(res, 409, 'parent missing', { 'Content-Type': 'text/plain' });
        if (exists && fs.statSync(abs).isDirectory()) return reply(res, 405, 'is a collection', { 'Content-Type': 'text/plain' });
        let buf;
        try {
          buf = await readBody(req, maxFile);
        } catch {
          return reply(res, 413, 'file too large', { 'Content-Type': 'text/plain' });
        }
        const current = exists ? fs.statSync(abs).size : 0;
        if (dirSize(userRoot) - current + buf.length > quota) return reply(res, 507, 'quota exceeded', { 'Content-Type': 'text/plain' });
        const tmp = `${abs}.part-${process.pid}-${Date.now()}`;
        fs.writeFileSync(tmp, buf);
        fs.renameSync(tmp, abs);
        return reply(res, exists ? 204 : 201, '', { 'Content-Length': '0' });
      }
      case 'DELETE': {
        if (parts.length === 0) return reply(res, 403, 'forbidden', { 'Content-Type': 'text/plain' });
        if (!exists) return reply(res, 404, 'not found', { 'Content-Type': 'text/plain' });
        fs.rmSync(abs, { recursive: true, force: true });
        return reply(res, 204, '', { 'Content-Length': '0' });
      }
      case 'MKCOL': {
        if (parts.length === 0) return reply(res, 405, 'method not allowed', { 'Content-Type': 'text/plain' });
        if (exists) return reply(res, 405, 'exists', { 'Content-Type': 'text/plain' });
        const parent = path.dirname(abs);
        if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) return reply(res, 409, 'parent missing', { 'Content-Type': 'text/plain' });
        fs.mkdirSync(abs);
        return reply(res, 201, '', { 'Content-Length': '0' });
      }
      case 'MOVE': {
        if (!exists || parts.length === 0) return reply(res, 404, 'not found', { 'Content-Type': 'text/plain' });
        const dest = String(req.headers.destination ?? '');
        let destPath;
        try {
          destPath = dest.startsWith('/') ? dest : new URL(dest).pathname;
        } catch {
          return reply(res, 400, 'bad destination', { 'Content-Type': 'text/plain' });
        }
        const dparts = partsOf(destPath.replace(/\/+$/, ''));
        if (dparts === null || dparts.length === 0 || !destPath.startsWith('/dav/')) return reply(res, 400, 'bad destination', { 'Content-Type': 'text/plain' });
        const dabs = entry(userRoot, dparts);
        if (!dabs) return reply(res, 400, 'bad destination', { 'Content-Type': 'text/plain' });
        const overwrite = String(req.headers.overwrite ?? 'T').toUpperCase() !== 'F';
        const dexists = fs.existsSync(dabs);
        if (dexists && !overwrite) return reply(res, 412, 'exists', { 'Content-Type': 'text/plain' });
        if (!fs.existsSync(path.dirname(dabs))) return reply(res, 409, 'parent missing', { 'Content-Type': 'text/plain' });
        if (dexists) fs.rmSync(dabs, { recursive: true, force: true });
        fs.renameSync(abs, dabs);
        return reply(res, dexists ? 204 : 201, '', { 'Content-Length': '0' });
      }
      default:
        return reply(res, 405, 'method not allowed', { 'Content-Type': 'text/plain' });
    }
  }

  return { handle, root };
}
