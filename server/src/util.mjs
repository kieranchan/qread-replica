// Small helpers: crypto, errors, rate limiting, request parsing.
import crypto from 'node:crypto';

export class ApiError extends Error {
  constructor(code, msg, status = 200) {
    super(msg);
    this.code = code;
    this.msg = msg;
    this.status = status;
  }
}

// Response codes of the account/cloud API (see docs/API.md): 0 ok, -5 "no data stored", other non-zero = failure
export const CODE = { OK: 0, ERR: -1, NEED_LOGIN: -2, NEED_VIP: -3, NO_DATA: -5 };

export const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
export const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');
export const newToken = () => crypto.randomBytes(24).toString('base64url');

export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = crypto.scryptSync(password, salt, 32);
  return `scrypt$${salt.toString('hex')}$${key.toString('hex')}`;
}

export function verifyPassword(password, stored) {
  const [alg, saltHex, keyHex] = String(stored).split('$');
  if (alg !== 'scrypt' || !saltHex || !keyHex) return false;
  const key = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), 32);
  const want = Buffer.from(keyHex, 'hex');
  return key.length === want.length && crypto.timingSafeEqual(key, want);
}

// activation codes: QR-XXXX-XXXX-XXXX, Crockford base32 without I L O U (60 random bits)
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export function newVipCode() {
  const bytes = crypto.randomBytes(12);
  let s = '';
  for (let i = 0; i < 12; i++) s += ALPHABET[bytes[i] & 31];
  return `QR-${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
}
export const newInviteCode = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
export const normalizeCode = (c) => String(c ?? '').toUpperCase().replace(/[^0-9A-Z]/g, '');

// sliding-window limiter, in memory (single process)
export class RateLimiter {
  constructor() {
    this.hits = new Map();
  }
  // returns true when the call is allowed (and records it)
  allow(key, max, windowMs, now = Date.now()) {
    const arr = (this.hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (arr.length >= max) {
      this.hits.set(key, arr);
      return false;
    }
    arr.push(now);
    this.hits.set(key, arr);
    if (this.hits.size > 10000) this.sweep(windowMs, now);
    return true;
  }
  // only count failures: check first, record on failure
  blocked(key, max, windowMs, now = Date.now()) {
    const arr = (this.hits.get(key) ?? []).filter((t) => now - t < windowMs);
    this.hits.set(key, arr);
    return arr.length >= max;
  }
  fail(key, now = Date.now()) {
    const arr = this.hits.get(key) ?? [];
    arr.push(now);
    this.hits.set(key, arr);
  }
  reset(key) {
    this.hits.delete(key);
  }
  sweep(windowMs, now) {
    for (const [k, v] of this.hits) if (!v.some((t) => now - t < windowMs)) this.hits.delete(k);
  }
}

export function parseMultipart(buf, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType);
  if (!m) return { fields: {}, files: {} };
  const boundary = Buffer.from('--' + (m[1] ?? m[2]));
  const fields = {};
  const files = {};
  let pos = buf.indexOf(boundary);
  while (pos !== -1) {
    const start = pos + boundary.length;
    if (buf[start] === 0x2d && buf[start + 1] === 0x2d) break; // closing "--"
    const next = buf.indexOf(boundary, start);
    if (next === -1) break;
    // part = CRLF headers CRLFCRLF body CRLF
    const part = buf.subarray(start + 2, next - 2);
    const headEnd = part.indexOf('\r\n\r\n');
    if (headEnd !== -1) {
      const head = part.subarray(0, headEnd).toString('utf8');
      const body = part.subarray(headEnd + 4);
      const name = /name="([^"]*)"/i.exec(head)?.[1];
      const filename = /filename="([^"]*)"/i.exec(head)?.[1];
      if (name !== undefined) {
        if (filename !== undefined) files[name] = { filename, data: body };
        else fields[name] = body.toString('utf8');
      }
    }
    pos = next;
  }
  return { fields, files };
}

export async function readBody(req, limit) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > limit) throw new ApiError(CODE.ERR, 'request too large', 413);
    chunks.push(c);
  }
  return Buffer.concat(chunks);
}

export const isEmail = (s) => /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/.test(s) && s.length <= 254;
export const isUsername = (s) => /^[A-Za-z0-9_.\-一-鿿]{3,32}$/.test(s);
export const fmtDate = (ms) => (ms > 0 ? new Date(ms).toISOString().slice(0, 10) : '');
