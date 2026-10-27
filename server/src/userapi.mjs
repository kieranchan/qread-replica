// Account / membership / cloud-sync endpoints with the wire contract recovered from the app (docs/API.md).
// Every handler gets a context { p: merged params, files, ip, now } and returns the JSON object to send.
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

  h.check_update = () => ({ code: 0, updateUrl: '', description: '' });

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
  const autoDevices = (kind) => (c) => {
    const { user } = auth(c);
    return ok(svc.db.prepare('SELECT appid, platform, model FROM auto_devices WHERE user_id = ? AND kind = ? ORDER BY updated_at DESC').all(user.id, kind));
  };
  const removeAuto = (kind) => (c) => {
    const { user } = auth(c);
    svc.db.prepare('DELETE FROM auto_devices WHERE user_id = ? AND kind = ? AND appid = ?').run(user.id, kind, String(c.p.appid ?? ''));
    return ok();
  };
  h.getAutoDevice = autoDevices(1);
  h.getAuto2Device = autoDevices(2);
  h.removeAutoDevice = removeAuto(1);
  h.removeAuto2Device = removeAuto(2);

  function registerAutoDevice(user, kind, c) {
    const appid = String(c.p.appid ?? '');
    if (!appid) return;
    const have = svc.db.prepare('SELECT 1 AS x FROM auto_devices WHERE user_id = ? AND kind = ? AND appid = ?').get(user.id, kind, appid);
    if (!have && !svc.isVip(user, c.now)) {
      const n = svc.db.prepare('SELECT COUNT(*) AS n FROM auto_devices WHERE user_id = ? AND kind = ?').get(user.id, kind).n;
      if (n >= cfg.freeBackupDevices) throw new ApiError(CODE.ERR, `非会员最多只能备份 ${cfg.freeBackupDevices} 个设备，请先删除旧设备`);
    }
    const tok = svc.db.prepare('SELECT platform, model FROM tokens WHERE user_id = ? AND appid = ?').get(user.id, appid) ?? { platform: '', model: '' };
    svc.db
      .prepare('INSERT INTO auto_devices(user_id, kind, appid, platform, model, updated_at) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id, kind, appid) DO UPDATE SET updated_at=excluded.updated_at')
      .run(user.id, kind, appid, tok.platform, tok.model, c.now);
  }

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
      return ok(String(c.p.etag ?? '') === b.etag ? '' : b.etag); // non-empty = newer data exists
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
    const data = JSON.stringify({ index: c.p.index, pos: c.p.pos, bid: c.p.bid, validateDocument: c.p.validateDocument, whiteSpace: c.p.whiteSpace });
    svc.db
      .prepare('INSERT INTO reads(user_id, book, appid, data, updated_at) VALUES (?,?,?,?,?) ON CONFLICT(user_id, book) DO UPDATE SET appid=excluded.appid, data=excluded.data, updated_at=excluded.updated_at')
      .run(user.id, `pos:${book}`, String(c.p.appid ?? ''), data, c.now);
    return ok();
  };
  const progressFor = (user, appid, now) =>
    svc.db
      .prepare('SELECT book, appid, data, updated_at FROM reads WHERE user_id = ? AND book LIKE ? AND appid != ? AND updated_at > ?')
      .all(user.id, 'pos:%', appid, now - 7 * 86_400_000)
      .map((r) => ({ book: r.book.slice(4), appid: r.appid, ...JSON.parse(r.data), t: r.updated_at }));
  h.openAuto = (c) => {
    const { user } = cloud(c);
    registerAutoDevice(user, 1, c);
    return ok(progressFor(user, String(c.p.appid ?? ''), c.now));
  };
  h.newopenAuto2 = (c) => {
    const { user } = cloud(c);
    registerAutoDevice(user, 2, c);
    return ok({ source: [], rss: [] });
  };

  // restore-from-backup lists (read only: the app's backup upload path is not recovered yet, see docs/API.md)
  const backupList = (kind) => (c) => {
    const { user } = cloud(c);
    const b = svc.getBlob(user.id, `backup:${kind}`);
    return b ? ok(b.data) : noData();
  };
  h.getBookSelf = backupList('books');
  h.getRss = backupList('rss');
  h.getSources = backupList('sources');

  return h;
}
