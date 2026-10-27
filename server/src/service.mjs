// Domain logic shared by the HTTP API and the admin CLI: accounts, tokens, membership, activation codes.
import { tx } from './db.mjs';
import {
  ApiError, CODE, hashPassword, verifyPassword, newToken, sha256, newVipCode, newInviteCode, normalizeCode,
  isEmail, isUsername,
} from './util.mjs';

const DAY = 86_400_000;
let DUMMY_HASH = null; // verified against when the user does not exist, so timing does not reveal valid names

export class Service {
  constructor(db, cfg) {
    this.db = db;
    this.cfg = cfg;
  }

  // ---- users ----
  createUser({ username, email, password, nickname = '', days = 0, now = Date.now() }) {
    if (!isUsername(username)) throw new ApiError(CODE.ERR, '用户名需为 3-32 位字母、数字、下划线、点、减号或汉字');
    if (!isEmail(email)) throw new ApiError(CODE.ERR, '邮箱格式不正确');
    if (typeof password !== 'string' || password.length < 6 || password.length > 128) throw new ApiError(CODE.ERR, '密码长度需为 6-128 位');
    return tx(this.db, () => {
      const dup = this.db.prepare('SELECT 1 FROM users WHERE username = ? OR email = ?').get(username, email);
      if (dup) throw new ApiError(CODE.ERR, '用户名或邮箱已被注册');
      const r = this.db
        .prepare('INSERT INTO users(username, email, pass_hash, nickname, vip_until, created_at) VALUES (?,?,?,?,?,?)')
        .run(username, email, hashPassword(password), nickname || username, 0, now);
      const id = Number(r.lastInsertRowid);
      if (days > 0) this.addDays(id, days, 'admin', 'create', now);
      return this.getUser(id);
    });
  }

  getUser(id) {
    return this.db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  }

  findUser(nameOrEmail) {
    return this.db.prepare('SELECT * FROM users WHERE username = ? OR email = ?').get(nameOrEmail, nameOrEmail);
  }

  setPassword(userId, password) {
    if (typeof password !== 'string' || password.length < 6 || password.length > 128) throw new ApiError(CODE.ERR, '密码长度需为 6-128 位');
    this.db.prepare('UPDATE users SET pass_hash = ? WHERE id = ?').run(hashPassword(password), userId);
    this.db.prepare('DELETE FROM tokens WHERE user_id = ?').run(userId); // force re-login everywhere
  }

  checkPassword(user, password) {
    if (!user) {
      DUMMY_HASH ??= hashPassword('dummy-password');
      verifyPassword(String(password ?? ''), DUMMY_HASH);
      return false;
    }
    return !user.disabled && verifyPassword(String(password ?? ''), user.pass_hash);
  }

  // ---- tokens / devices ----
  issueToken(user, { appid = '', platform = '', model = '' }, now = Date.now()) {
    const token = newToken();
    tx(this.db, () => {
      if (appid) this.db.prepare('DELETE FROM tokens WHERE user_id = ? AND appid = ?').run(user.id, appid);
      const n = this.db.prepare('SELECT COUNT(*) AS n FROM tokens WHERE user_id = ?').get(user.id).n;
      if (n >= this.cfg.maxLoginDevices) {
        // drop the least recently used device
        this.db.prepare('DELETE FROM tokens WHERE hash = (SELECT hash FROM tokens WHERE user_id = ? ORDER BY last_seen LIMIT 1)').run(user.id);
      }
      this.db
        .prepare('INSERT INTO tokens(hash, user_id, appid, platform, model, created_at, last_seen, expires_at) VALUES (?,?,?,?,?,?,?,?)')
        .run(sha256(token), user.id, String(appid).slice(0, 128), String(platform).slice(0, 32), String(model).slice(0, 128), now, now,
          now + this.cfg.tokenTtlDays * DAY);
    });
    return token;
  }

  // returns { user, tokenRow } or throws NEED_LOGIN
  authenticate(token, now = Date.now()) {
    if (!token || typeof token !== 'string' || token.length > 200) throw new ApiError(CODE.NEED_LOGIN, 'NEED_LOGIN');
    const row = this.db.prepare('SELECT * FROM tokens WHERE hash = ?').get(sha256(token));
    if (!row || row.expires_at < now) throw new ApiError(CODE.NEED_LOGIN, 'NEED_LOGIN');
    const user = this.getUser(row.user_id);
    if (!user || user.disabled) throw new ApiError(CODE.NEED_LOGIN, 'NEED_LOGIN');
    if (now - row.last_seen > 60_000) this.db.prepare('UPDATE tokens SET last_seen = ? WHERE hash = ?').run(now, row.hash);
    return { user, tokenRow: row };
  }

  revokeToken(token) {
    this.db.prepare('DELETE FROM tokens WHERE hash = ?').run(sha256(token));
  }

  loginDevices(userId) {
    return this.db.prepare('SELECT appid, platform, model, last_seen FROM tokens WHERE user_id = ? ORDER BY last_seen DESC').all(userId);
  }

  removeLoginDevice(userId, appid) {
    return Number(this.db.prepare('DELETE FROM tokens WHERE user_id = ? AND appid = ?').run(userId, appid).changes);
  }

  // ---- membership ----
  isVip(user, now = Date.now()) {
    return user.vip_until > now;
  }

  // adds (or, when negative, removes) days; an expired membership restarts from now
  addDays(userId, days, source, ref = '', now = Date.now()) {
    return tx(this.db, () => {
      const u = this.getUser(userId);
      const base = Math.max(u.vip_until, now);
      const next = days >= 0 ? base + days * DAY : Math.max(0, u.vip_until + days * DAY);
      this.db.prepare('UPDATE users SET vip_until = ? WHERE id = ?').run(next, userId);
      this.db.prepare('INSERT INTO vip_log(user_id, delta_days, source, ref, at) VALUES (?,?,?,?,?)').run(userId, days, source, ref, now);
      return next;
    });
  }

  revokeVip(userId, now = Date.now()) {
    this.db.prepare('UPDATE users SET vip_until = 0 WHERE id = ?').run(userId);
    this.db.prepare('INSERT INTO vip_log(user_id, delta_days, source, ref, at) VALUES (?,?,?,?,?)').run(userId, 0, 'admin', 'revoke', now);
  }

  // ---- codes ----
  makeCodes({ kind, count = 1, days = 0, note = '', validDays = 0, now = Date.now() }) {
    if (!['vip', 'invite'].includes(kind)) throw new Error('kind must be vip or invite');
    const out = [];
    tx(this.db, () => {
      const ins = this.db.prepare('INSERT INTO codes(code_hash, kind, days, note, created_at, valid_until) VALUES (?,?,?,?,?,?)');
      for (let i = 0; i < count; i++) {
        for (let tries = 0; tries < 20; tries++) {
          const code = kind === 'vip' ? newVipCode() : newInviteCode();
          try {
            ins.run(sha256(normalizeCode(code)), kind, days, note, now, validDays > 0 ? now + validDays * DAY : 0);
            out.push(code);
            break;
          } catch (e) {
            if (!/UNIQUE/.test(String(e.message))) throw e;
          }
        }
      }
    });
    return out;
  }

  // atomically marks a code used. Returns the code row; throws ApiError when unknown/used/expired/wrong kind.
  consumeCode(code, kind, userId, now = Date.now()) {
    const hash = sha256(normalizeCode(code));
    return tx(this.db, () => {
      const row = this.db.prepare('SELECT * FROM codes WHERE code_hash = ? AND kind = ?').get(hash, kind);
      if (!row || row.used_at) throw new ApiError(CODE.ERR, kind === 'vip' ? '激活码无效或已使用' : '验证码无效或已使用');
      if (row.valid_until && row.valid_until < now) throw new ApiError(CODE.ERR, '激活码已过期');
      this.db.prepare('UPDATE codes SET used_by = ?, used_at = ? WHERE id = ?').run(userId ?? null, now, row.id);
      return row;
    });
  }

  redeem(userId, code, now = Date.now()) {
    return tx(this.db, () => {
      const row = this.consumeCode(code, 'vip', userId, now);
      return this.addDays(userId, row.days, 'code', `code#${row.id}`, now);
    });
  }

  // registration with an invite code (kind 'invite'); the user is created and the code consumed in one transaction
  register({ username, email, password, code, now = Date.now() }) {
    if (this.cfg.register === 'closed') throw new ApiError(CODE.ERR, '当前不开放注册，请联系管理员');
    return tx(this.db, () => {
      const row = this.consumeCode(code, 'invite', null, now);
      const user = this.createUser({ username, email, password, now });
      this.db.prepare('UPDATE codes SET used_by = ? WHERE id = ?').run(user.id, row.id);
      if (row.days > 0) this.addDays(user.id, row.days, 'register', `code#${row.id}`, now);
      return this.getUser(user.id);
    });
  }

  // ---- cloud blobs ----
  putBlob(userId, kind, data, md5, now = Date.now()) {
    this.db
      .prepare('INSERT INTO blobs(user_id, kind, data, etag, updated_at) VALUES (?,?,?,?,?) ON CONFLICT(user_id, kind) DO UPDATE SET data=excluded.data, etag=excluded.etag, updated_at=excluded.updated_at')
      .run(userId, kind, data, md5, now);
  }

  getBlob(userId, kind) {
    return this.db.prepare('SELECT data, etag, updated_at FROM blobs WHERE user_id = ? AND kind = ?').get(userId, kind);
  }

  deleteBlob(userId, kind) {
    return Number(this.db.prepare('DELETE FROM blobs WHERE user_id = ? AND kind = ?').run(userId, kind).changes);
  }
}
