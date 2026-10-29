// Account / membership / cloud-sync endpoints with the wire contract recovered from the app (docs/API.md).
// Every handler gets a context { p: merged params, files, ip, now } and returns the JSON object to send.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { ApiError, CODE, RateLimiter, md5, sha256, fmtDate, isEmail } from './util.mjs';

const MIN = 60_000;
const ITEM_RE = /^[A-Za-z0-9_.\-]{1,64}$/;
const LISTS = [
  { kind: 'books', etag: 'getEtag', upd: 'getBookUpdateurl', list: 'getBooks' },
  { kind: 'rss', etag: 'getBRssEtag', upd: 'getBRssUpdateurl', list: 'getBRss' },
  { kind: 'sources', etag: 'getBSourceEtag', upd: 'getBSourceUpdateurl', list: 'getBSource' },
  { kind: 'notes', etag: 'getBjEtag', upd: 'getBjUpdateurl', list: 'getBjs' },
  { kind: 'groups', etag: 'getGroupEtag', upd: 'getGroupUpdateurl', list: 'getGroups' },
];
// item names that are really one of the list kinds (the app uploads lists through setItemJsonFile)
const LIST_ALIAS = { books: 'books', phone_book: 'books', rss: 'rss', brss: 'rss', sources: 'sources', source: 'sources', bsource: 'sources',
  notes: 'notes', bj: 'notes', note: 'notes', groups: 'groups', group: 'groups' };

function sniffImage(buf) {
  if (buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'png';
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg';
  if (buf.length > 6 && buf.subarray(0, 4).toString('latin1') === 'GIF8') return 'gif';
  if (buf.length > 12 && buf.subarray(0, 4).toString('latin1') === 'RIFF' && buf.subarray(8, 12).toString('latin1') === 'WEBP') return 'webp';
  return null;
}

// The release announced by check_update (written by `admin set-update`), or null.
export function updateFile(dataDir) {
  return path.join(dataDir, 'static', 'update.json');
}
export function parseUpdate(j) {
  if (!j || typeof j !== 'object' || Array.isArray(j)) throw new Error('update file must be a JSON object');
  const build = Number(j.build);
  if (!Number.isInteger(build) || build < 1) throw new Error('build must be a positive integer (the build number after + in pubspec version)');
  const url = String(j.url ?? '');
  if (!/^https?:\/\/\S+$/.test(url)) throw new Error('url must be an http(s) link');
  const platform = String(j.platform ?? '');
  if (platform && !/^[a-z]{2,16}$/.test(platform)) throw new Error('platform must be like ios');
  return { version: String(j.version ?? ''), build, notes: String(j.notes ?? ''), url, ...(platform ? { platform } : {}) };
}
function readUpdate(dataDir) {
  try {
    return parseUpdate(JSON.parse(fs.readFileSync(updateFile(dataDir), 'utf8')));
  } catch {
    return null;
  }
}

export function createUserApi(svc, cfg, limiter = new RateLimiter()) {
  const imgDir = path.join(cfg.dataDir, 'images');
  const urlOf = (file) => (file ? `${cfg.baseUrl}/images/${file}` : '');

  const ok = (data) => (data === undefined ? { code: 0 } : { code: 0, data });
  const noData = () => ({ code: CODE.NO_DATA });

  const auth = (c) => svc.authenticate(c.p.tockenid, c.now);
  const needVip = (user, now) => {
    if (cfg.cloudNeedsVip && !svc.isVip(user, now)) throw new ApiError(CODE.NEED_VIP, '云端功能需要会员权限');
  };
  const cloud = (c) => {
    const a = auth(c);
    needVip(a.user, c.now);
    return a;
  };

  // Userinfo contract of the app (docs/API.md): `id` is the session token (the app stores that slot as `tockenid`), `vip` is a
  // display string for the membership ("永久", a date, or "" for non-members). Extra keys (`userId`, `vipUntil`) are ignored by the app.
  const FIFTY_YEARS = 50 * 365 * 86_400_000;
  function vipText(user, now) {
    if (!svc.isVip(user, now)) return '';
    return user.vip_until - now > FIFTY_YEARS ? '永久' : fmtDate(user.vip_until);
  }
  function userInfo(user, token, now) {
    return {
      username: user.username,
      id: token,
      vip: vipText(user, now),
      isvip: svc.isVip(user, now),
      avatar_url: urlOf(user.avatar),
      nickname: user.nickname || user.username,
      email: user.email,
      userId: String(user.id),
      vipUntil: user.vip_until,
    };
  }

  const h = {};

  // ---------------- accounts (no token) ----------------
  h.login = (c) => {
    const { username, password, appid = '', platform = '', model = '' } = c.p;
    const k1 = `login:${c.ip}:${String(username).toLowerCase()}`;
    const k2 = `login-ip:${c.ip}`;
    if (limiter.blocked(k1, 8, 10 * MIN, c.now) || limiter.blocked(k2, 40, 10 * MIN, c.now)) throw new ApiError(CODE.ERR, '尝试次数过多，请稍后再试');
    const user = svc.findUser(String(username ?? ''));
    if (!svc.checkPassword(user, password)) {
      limiter.fail(k1, c.now);
      limiter.fail(k2, c.now);
      throw new ApiError(CODE.ERR, '用户名或密码错误');
    }
    limiter.reset(k1);
    const token = svc.issueToken(user, { appid, platform, model }, c.now);
    return ok(userInfo(user, token, c.now));
  };

  h.getEmailCode = (c) => {
    if (!limiter.allow(`mail:${c.ip}`, 10, 10 * MIN, c.now)) throw new ApiError(CODE.ERR, '请求过于频繁');
    if (!isEmail(String(c.p.email ?? ''))) throw new ApiError(CODE.ERR, '邮箱格式不正确');
    return ok(); // no mail is sent: registration needs the admin-issued 6-digit code (cfg.register)
  };

  h.register = (c) => {
    if (limiter.blocked(`reg:${c.ip}`, 8, 10 * MIN, c.now)) throw new ApiError(CODE.ERR, '尝试次数过多，请稍后再试');
    try {
      svc.register({ username: String(c.p.username ?? ''), email: String(c.p.email ?? ''), password: c.p.password, code: c.p.code, now: c.now });
    } catch (e) {
      limiter.fail(`reg:${c.ip}`, c.now);
      throw e;
    }
    return ok();
  };

  h.forgetPassword = () => {
    throw new ApiError(CODE.ERR, '未开启邮件找回，请联系管理员重置密码');
  };

  // Update check (the app's 关于 page and its main-page start-up, 0x1078878): `check_update?platform=&version=<build number>&t=`.
  // The original reads `code` (0 = a newer build exists), `updateUrl`, `description`. The answer comes from the release the owner set
  // with `qread-admin set-update <file.json>` (data/static/update.json: version, build, notes, url, optional platform).
  h.check_update = (c) => {
    const rel = readUpdate(cfg.dataDir);
    const none = { code: CODE.ERR, errorMsg: '已是最新版本' };
    if (!rel) return none;
    if (rel.platform && String(c.p.platform ?? '') !== rel.platform) return none;
    const current = Number.parseInt(String(c.p.version ?? ''), 10);
    if (Number.isFinite(current) && current >= rel.build) return none;
    return { code: 0, updateUrl: rel.url, description: rel.notes, version: rel.version, build: rel.build };
  };

  // ---------------- accounts (with token) ----------------
  h.getUserInfo = (c) => {
    const { user } = auth(c);
    return ok(userInfo(user, c.p.tockenid, c.now));
  };
  h.logout = (c) => {
    auth(c);
    svc.revokeToken(c.p.tockenid);
    return ok();
  };
  h.cleanuser = (c) => {
    const { user } = auth(c);
    svc.db.prepare('DELETE FROM blobs WHERE user_id = ?').run(user.id);
    svc.db.prepare('DELETE FROM reads WHERE user_id = ?').run(user.id);
    svc.db.prepare('DELETE FROM auto_devices WHERE user_id = ?').run(user.id);
    svc.db.prepare('DELETE FROM auto_backups WHERE user_id = ?').run(user.id);
    return ok();
  };
  h.updateNickname = (c) => {
    const { user } = auth(c);
    const nick = String(c.p.nickname ?? '').trim();
    if (nick.length < 1 || nick.length > 32) throw new ApiError(CODE.ERR, '昵称长度需为 1-32 个字符');
    svc.db.prepare('UPDATE users SET nickname = ? WHERE id = ?').run(nick, user.id);
    return ok();
  };
  h.changePassword = (c) => {
    const { user } = auth(c);
    if (!limiter.allow(`chpw:${user.id}`, 8, 10 * MIN, c.now)) throw new ApiError(CODE.ERR, '尝试次数过多，请稍后再试');
    if (!svc.checkPassword(user, c.p.oldpassword)) throw new ApiError(CODE.ERR, '原密码错误');
    svc.setPassword(user.id, c.p.newpassword);
    return ok();
  };

  function saveImage(buf, name) {
    const ext = sniffImage(buf);
    if (!ext) throw new ApiError(CODE.ERR, '不支持的图片格式');
    fs.mkdirSync(imgDir, { recursive: true });
    const file = `${name}.${ext}`;
    const p = path.join(imgDir, file);
    if (!fs.existsSync(p)) fs.writeFileSync(p, buf);
    return file;
  }
  h.updateAvatar = (c) => {
    const { user } = auth(c);
    const f = c.files.file;
    if (!f || f.data.length > 2 * 1024 * 1024) throw new ApiError(CODE.ERR, '头像需小于 2MB');
    const file = saveImage(f.data, `avatar-${sha256(f.data).slice(0, 32)}`);
    svc.db.prepare('UPDATE users SET avatar = ? WHERE id = ?').run(file, user.id);
    return ok({ avatar_url: urlOf(file) });
  };
  h.imgupload = (c) => {
    auth(c);
    const f = c.files.file;
    if (!f || f.data.length > 8 * 1024 * 1024) throw new ApiError(CODE.ERR, '图片需小于 8MB');
    const sum = md5(f.data);
    if (c.p.md5 && String(c.p.md5).toLowerCase() !== sum) throw new ApiError(CODE.ERR, 'md5 不匹配');
    const file = saveImage(f.data, sum);
    svc.db.prepare('INSERT OR IGNORE INTO images(md5, file, created_at) VALUES (?,?,?)').run(sum, file, c.now);
    return { code: 0, message: urlOf(file), url: urlOf(file) };
  };
  h.upload = (c) => {
    auth(c);
    const f = c.files.file;
    if (!f || f.data.length > 8 * 1024 * 1024) throw new ApiError(CODE.ERR, '图片需小于 8MB');
    const file = saveImage(f.data, md5(f.data));
    return { code: 0, url: urlOf(file), message: 'ok' };
  };
  h.hasimg = (c) => {
    auth(c);
    const row = svc.db.prepare('SELECT 1 AS x FROM images WHERE md5 = ?').get(String(c.p.md5 ?? '').toLowerCase());
    return row ? ok() : noData();
  };

  // ---------------- diagnostics ----------------
  // The app's self-check page posts its results here so they can be read on the server (admin `list-diag`, journal) without
  // touching the phone.
  h.diag = (c) => {
    const { user } = auth(c);
    if (!limiter.allow(`diag:${user.id}`, 30, 60 * MIN, c.now)) throw new ApiError(CODE.ERR, '上报过于频繁');
    const results = (Array.isArray(c.p.results) ? c.p.results : []).slice(0, 100).map((r) => ({
      name: String(r?.name ?? '').slice(0, 80),
      ok: r?.ok === true,
      detail: String(r?.detail ?? '').slice(0, 300),
    }));
    const body = JSON.stringify({ app: String(c.p.app ?? '').slice(0, 60), platform: String(c.p.platform ?? '').slice(0, 32), model: String(c.p.model ?? '').slice(0, 64), results });
    const r = svc.db.prepare('INSERT INTO diag_reports(user_id, appid, at, body) VALUES (?,?,?,?)').run(user.id, String(c.p.appid ?? '').slice(0, 128), c.now, body);
    svc.db.prepare('DELETE FROM diag_reports WHERE user_id = ? AND id NOT IN (SELECT id FROM diag_reports WHERE user_id = ? ORDER BY id DESC LIMIT 200)').run(user.id, user.id);
    const okN = results.filter((x) => x.ok).length;
    if (cfg.log) console.log(JSON.stringify({ diag: { user: user.username, appid: c.p.appid, ok: okN, fail: results.length - okN } }));
    return ok({ id: Number(r.lastInsertRowid), ok: okN, fail: results.length - okN });
  };

  // ---------------- devices ----------------
  h.getloginDevice = (c) => {
    const { user } = auth(c);
    return ok(svc.loginDevices(user.id).map((d) => ({ appid: d.appid, platform: d.platform, model: d.model, time: d.last_seen })));
  };
  h.removeDevice = (c) => {
    const { user } = auth(c);
    svc.removeLoginDevice(user.id, String(c.p.appid ?? ''));
    return ok();
  };
  // Backup devices (the original's 书架备份 = kind 1, 书源备份 = kind 2; docs/API.md "Backup devices").
  const PARTS = { 1: ['books'], 2: ['sources', 'rss'] };
  const autoDevices = (kind) => (c) => {
    const { user } = auth(c);
    return ok(svc.db.prepare('SELECT appid, platform, model FROM auto_devices WHERE user_id = ? AND kind = ? ORDER BY updated_at DESC').all(user.id, kind));
  };
  const removeAuto = (kind) => (c) => {
    const { user } = auth(c);
    const appid = String(c.p.appid ?? '');
    svc.db.prepare('DELETE FROM auto_devices WHERE user_id = ? AND kind = ? AND appid = ?').run(user.id, kind, appid);
    for (const part of PARTS[kind]) svc.db.prepare('DELETE FROM auto_backups WHERE user_id = ? AND part = ? AND appid = ?').run(user.id, part, appid);
    return ok();
  };
  h.getAutoDevice = autoDevices(1);
  h.getAuto2Device = autoDevices(2);
  h.removeAutoDevice = removeAuto(1);
  h.removeAuto2Device = removeAuto(2);

  const isRegistered = (user, kind, appid) => !!svc.db.prepare('SELECT 1 AS x FROM auto_devices WHERE user_id = ? AND kind = ? AND appid = ?').get(user.id, kind, appid);

  // st "0": the user switched the backup on (registers the device; free accounts keep at most cfg.freeBackupDevices);
  // st "1": the app re-opens the backup at start-up (the device must still be registered: removing it from another device
  // makes the app switch its backup off, as the original does when openAuto fails).
  function registerAutoDevice(user, kind, c) {
    const appid = String(c.p.appid ?? '');
    if (!appid || appid.length > 128) throw new ApiError(CODE.ERR, '缺少设备标识');
    const have = isRegistered(user, kind, appid);
    if (!have && String(c.p.st ?? '0') === '1') throw new ApiError(CODE.ERR, kind === 1 ? '此设备已从书架备份中移除，请重新开启备份' : '此设备已从书源备份中移除，请重新开启备份');
    if (!have && !svc.isVip(user, c.now)) {
      const n = svc.db.prepare('SELECT COUNT(*) AS n FROM auto_devices WHERE user_id = ? AND kind = ?').get(user.id, kind).n;
      if (n >= cfg.freeBackupDevices) throw new ApiError(CODE.ERR, `非会员最多只能备份 ${cfg.freeBackupDevices} 个设备，请先在书架备份中删除旧设备`);
    }
    const tok = svc.db.prepare('SELECT platform, model FROM tokens WHERE user_id = ? AND appid = ? ORDER BY last_seen DESC').get(user.id, appid) ?? { platform: '', model: '' };
    svc.db
      .prepare('INSERT INTO auto_devices(user_id, kind, appid, platform, model, updated_at) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id, kind, appid) DO UPDATE SET updated_at=excluded.updated_at, platform=excluded.platform, model=excluded.model')
      .run(user.id, kind, appid, tok.platform, tok.model, c.now);
    return appid;
  }

  // the url of one backup part of a device (created on first use, stable afterwards)
  function backupUrl(user, part, appid, now) {
    let row = svc.db.prepare('SELECT key FROM auto_backups WHERE user_id = ? AND part = ? AND appid = ?').get(user.id, part, appid);
    if (!row) {
      row = { key: crypto.randomBytes(16).toString('hex') };
      svc.db.prepare('INSERT INTO auto_backups(key, user_id, appid, part, data, updated_at) VALUES (?,?,?,?,NULL,?)').run(row.key, user.id, appid, part, now);
    }
    return `${cfg.baseUrl}/autobackup/${row.key}`;
  }

  // openAuto (original 0xf223ac): {tockenid, appid, st, t} -> data = the upload url of this device's bookshelf backup (the app keeps
  // it in a static and PUTs the JSON book list there). Bookshelf backup is not a member feature (free accounts: 2 devices).
  h.openAuto = (c) => {
    const { user } = auth(c);
    const appid = registerAutoDevice(user, 1, c);
    return ok(backupUrl(user, 'books', appid, c.now));
  };
  // newopenAuto2 (0xf226c4): same for the source backup (member feature) -> data = {source, rss} upload urls.
  h.newopenAuto2 = (c) => {
    const { user } = auth(c);
    needVip(user, c.now);
    const appid = registerAutoDevice(user, 2, c);
    return ok({ source: backupUrl(user, 'sources', appid, c.now), rss: backupUrl(user, 'rss', appid, c.now) });
  };

  // getBookSelf (0xfa8894) / getSources (0x105127c) / getRss (0x1050ff4): {tockenid, appid = the backup device, t} -> data = the
  // download url of that device's backup; the app GETs it (404 = nothing uploaded yet: 此设备书源备份为空).
  const backupOf = (kind, part) => (c) => {
    const { user } = auth(c);
    if (kind === 2) needVip(user, c.now);
    const appid = String(c.p.appid ?? '');
    if (!isRegistered(user, kind, appid)) throw new ApiError(CODE.ERR, '备份设备不存在');
    return ok(backupUrl(user, part, appid, c.now));
  };
  h.getBookSelf = backupOf(1, 'books');
  h.getSources = backupOf(2, 'sources');
  h.getRss = backupOf(2, 'rss');

  // ---------------- membership ----------------
  h.canOpenCloud = (c) => {
    const { user } = auth(c);
    if (!svc.isVip(user, c.now)) throw new ApiError(CODE.NEED_VIP, '此功能为会员功能');
    return ok();
  };
  const redeem = (c, code) => {
    const { user } = auth(c);
    const key = `redeem:${user.id}`;
    if (limiter.blocked(key, 8, 10 * MIN, c.now)) throw new ApiError(CODE.ERR, '尝试次数过多，请稍后再试');
    try {
      const until = svc.redeem(user.id, code, c.now);
      return { until, expire: fmtDate(until) };
    } catch (e) {
      limiter.fail(key, c.now);
      throw e;
    }
  };
  // the app's purchase bridge: paymentType "code" carries an activation code in vipType (our replacement of StoreKit)
  h.paynew = (c) => {
    if (String(c.p.paymentType) !== 'code') throw new ApiError(CODE.ERR, '暂不支持');
    redeem(c, c.p.vipType);
    return ok('ok');
  };
  h.redeem = (c) => {
    const r = redeem(c, c.p.code);
    return ok({ ...r, isvip: true });
  };

  // ---------------- cloud sync ----------------
  for (const L of LISTS) {
    h[L.etag] = (c) => {
      const { user } = cloud(c);
      const b = svc.getBlob(user.id, L.kind);
      return b ? ok(b.etag) : noData();
    };
    h[L.upd] = (c) => {
      const { user } = cloud(c);
      const b = svc.getBlob(user.id, L.kind);
      if (!b) return noData();
      // as the app reads it (original 0xe6766c): the etag when the client is current, '' when newer data exists -> merge
      return ok(String(c.p.etag ?? '') === b.etag ? b.etag : '');
    };
    h[L.list] = (c) => {
      const { user } = cloud(c);
      const b = svc.getBlob(user.id, L.kind);
      return b ? ok(b.data) : noData();
    };
  }

  h.getItemJson = (c) => {
    const { user } = cloud(c);
    const item = String(c.p.item ?? '');
    if (!ITEM_RE.test(item)) throw new ApiError(CODE.ERR, 'bad item');
    const b = svc.getBlob(user.id, LIST_ALIAS[item] ?? `item:${item}`);
    return b ? ok(b.data) : noData();
  };
  h.getItemMd5 = (c) => {
    const { user } = cloud(c);
    const item = String(c.p.item ?? '');
    if (!ITEM_RE.test(item)) throw new ApiError(CODE.ERR, 'bad item');
    const b = svc.getBlob(user.id, LIST_ALIAS[item] ?? `item:${item}`);
    return b ? ok(b.etag) : noData();
  };
  h.setItemJsonFile = (c) => {
    const { user } = cloud(c);
    const item = String(c.p.item ?? '');
    if (!ITEM_RE.test(item)) throw new ApiError(CODE.ERR, 'bad item');
    const raw = c.files.file?.data ?? (typeof c.p.file === 'string' ? Buffer.from(c.p.file, 'utf8') : typeof c.p.data === 'string' ? Buffer.from(c.p.data, 'utf8') : null);
    if (!raw) throw new ApiError(CODE.ERR, '缺少文件');
    const text = raw.toString('utf8');
    const kind = LIST_ALIAS[item] ?? `item:${item}`;
    svc.putBlob(user.id, kind, text, md5(text), c.now);
    return ok();
  };

  h.addreads = (c) => {
    const { user } = cloud(c);
    const book = String(c.p.book ?? '');
    if (!book) throw new ApiError(CODE.ERR, 'bad book');
    svc.db
      .prepare('INSERT INTO reads(user_id, book, appid, data, updated_at) VALUES (?,?,?,?,?) ON CONFLICT(user_id, book) DO UPDATE SET appid=excluded.appid, data=excluded.data, updated_at=excluded.updated_at')
      .run(user.id, book, String(c.p.appid ?? ''), JSON.stringify({ readchapter: c.p.readchapter ?? '' }), c.now);
    return ok();
  };
  h.autopos = (c) => {
    const { user } = cloud(c);
    const book = String(c.p.book ?? '');
    if (!book) throw new ApiError(CODE.ERR, 'bad book');
    const data = JSON.stringify({ index: c.p.index, pos: c.p.pos, title: c.p.title ?? '', bid: c.p.bid, validateDocument: c.p.validateDocument, whiteSpace: c.p.whiteSpace });
    svc.db
      .prepare('INSERT INTO reads(user_id, book, appid, data, updated_at) VALUES (?,?,?,?,?) ON CONFLICT(user_id, book) DO UPDATE SET appid=excluded.appid, data=excluded.data, updated_at=excluded.updated_at')
      .run(user.id, `pos:${book}`, String(c.p.appid ?? ''), data, c.now);
    return ok();
  };
  // The stored position of a book (the app's 进度同步确认 compares it with the device's own progress when a book is opened and offers
  // 覆盖 / 跳转; the original app did this against the bound 轻阅读后端's record). `-5` when nothing is stored.
  h.getpos = (c) => {
    const { user } = cloud(c);
    const book = String(c.p.book ?? '');
    if (!book) throw new ApiError(CODE.ERR, 'bad book');
    const row = svc.db.prepare('SELECT appid, data, updated_at FROM reads WHERE user_id = ? AND book = ?').get(user.id, `pos:${book}`);
    if (!row) return noData();
    let d = {};
    try {
      d = JSON.parse(row.data) ?? {};
    } catch {
      d = {};
    }
    return ok({ index: Number(d.index ?? 0) || 0, pos: Number(d.pos ?? 0) || 0, title: String(d.title ?? ''), bid: String(d.bid ?? ''), appid: row.appid, t: row.updated_at });
  };
  return h;
}

// The upload / download side of the backup urls handed out above (`PUT|GET <base>/autobackup/<key>`, see server.mjs). The key is
// the capability, like the pre-signed object-storage urls of the original.
export function createAutoBackups(svc) {
  const KEY_RE = /^[0-9a-f]{32}$/;
  return {
    put(key, buf, now) {
      if (!KEY_RE.test(key)) return false;
      const r = svc.db.prepare('UPDATE auto_backups SET data = ?, updated_at = ? WHERE key = ?').run(buf, now, key);
      if (r.changes === 0) return false;
      const b = svc.db.prepare('SELECT user_id, appid, part FROM auto_backups WHERE key = ?').get(key);
      svc.db.prepare('UPDATE auto_devices SET updated_at = ? WHERE user_id = ? AND appid = ? AND kind = ?').run(now, b.user_id, b.appid, b.part === 'books' ? 1 : 2);
      return true;
    },
    get(key) {
      if (!KEY_RE.test(key)) return null;
      const row = svc.db.prepare('SELECT data FROM auto_backups WHERE key = ?').get(key);
      return row?.data == null ? null : Buffer.from(row.data);
    },
  };
}
