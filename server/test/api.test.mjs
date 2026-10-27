import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { createApp } from '../src/server.mjs';
import { run as admin } from '../src/admin.mjs';
import { loadConfig } from '../src/config.mjs';

let app, base, tmp;
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), crypto.randomBytes(40)]);

async function post(p, body, headers = {}) {
  const r = await fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { status: r.status, json: await r.json() };
}
async function multipart(p, query, fields, fileField, filename, data) {
  const boundary = '----t' + crypto.randomBytes(6).toString('hex');
  const parts = [];
  for (const [k, v] of Object.entries(fields)) parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
  parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${fileField}"; filename="${filename}"\r\nContent-Type: application/octet-stream\r\n\r\n`));
  parts.push(Buffer.isBuffer(data) ? data : Buffer.from(data));
  parts.push(Buffer.from(`\r\n--${boundary}--\r\n`));
  const r = await fetch(base + p + '?' + new URLSearchParams(query), { method: 'POST', headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}` }, body: Buffer.concat(parts) });
  return r.json();
}

// creates a user through the registration API with an invite code, logs in, returns the token
async function newUser(name, { days = 0, appid = 'dev-' + name } = {}) {
  const [inv] = app.svc.makeCodes({ kind: 'invite', count: 1, validDays: 1 });
  const reg = await post('/register', { username: name, email: `${name}@example.com`, password: 'secret-pw', code: inv });
  assert.equal(reg.json.code, 0, JSON.stringify(reg.json));
  const login = await post('/login', { username: name, password: 'secret-pw', platform: 'ios', model: 'iPhone', appid });
  assert.equal(login.json.code, 0, JSON.stringify(login.json));
  if (days) app.svc.addDays(login.json.data.id * 1, days, 'admin', 'test');
  return { token: login.json.data.vip, id: Number(login.json.data.id), info: login.json.data, appid };
}

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-test-'));
  app = createApp({ dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
  app.cfg.baseUrl = base;
});
after(async () => {
  await app.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('healthz and unknown endpoint', async () => {
  const h = await (await fetch(base + '/healthz')).json();
  assert.equal(h.ok, true);
  const r = await post('/doesNotExist', {});
  assert.equal(r.status, 404);
  const r2 = await post('/constructor', {});
  assert.equal(r2.status, 404);
});

test('register needs a valid invite code; codes are single use', async () => {
  const bad = await post('/register', { username: 'alice', email: 'a@example.com', password: 'secret-pw', code: '123456' });
  assert.notEqual(bad.json.code, 0);
  const [inv] = app.svc.makeCodes({ kind: 'invite' });
  const ok = await post('/register', { username: 'alice', email: 'a@example.com', password: 'secret-pw', code: inv });
  assert.equal(ok.json.code, 0);
  const again = await post('/register', { username: 'alice2', email: 'a2@example.com', password: 'secret-pw', code: inv });
  assert.notEqual(again.json.code, 0);
  // duplicate username does not burn a fresh code
  const [inv2] = app.svc.makeCodes({ kind: 'invite' });
  const dup = await post('/register', { username: 'ALICE', email: 'other@example.com', password: 'secret-pw', code: inv2 });
  assert.notEqual(dup.json.code, 0);
  const ok2 = await post('/register', { username: 'alice3', email: 'a3@example.com', password: 'secret-pw', code: inv2 });
  assert.equal(ok2.json.code, 0);
});

test('login returns the Userinfo contract; token is accepted, bad token is NEED_LOGIN', async () => {
  const u = await newUser('bob');
  const d = u.info;
  for (const k of ['username', 'id', 'vip', 'isvip', 'avatar_url', 'nickname', 'email']) assert.ok(k in d, k);
  assert.equal(typeof d.vip, 'string');
  assert.equal(d.isvip, false);
  const info = await post('/getUserInfo', { tockenid: u.token, appid: u.appid, t: Date.now() });
  assert.equal(info.json.code, 0);
  assert.equal(info.json.data.username, 'bob');
  const bad = await post('/getUserInfo', { tockenid: 'nope' });
  assert.equal(bad.json.code, -2);
  assert.equal(bad.json.errorMsg, 'NEED_LOGIN');
  // login by email works too
  const byMail = await post('/login', { username: 'bob@example.com', password: 'secret-pw', appid: 'x' });
  assert.equal(byMail.json.code, 0);
});

test('wrong password is rejected and rate limited', async () => {
  await newUser('carol');
  for (let i = 0; i < 8; i++) {
    const r = await post('/login', { username: 'carol', password: 'wrong' });
    assert.notEqual(r.json.code, 0);
  }
  const blocked = await post('/login', { username: 'carol', password: 'secret-pw' });
  assert.notEqual(blocked.json.code, 0);
  assert.match(blocked.json.errorMsg, /稍后/);
});

test('cloud features need membership; activation code grants it once', async () => {
  const u = await newUser('dave');
  const no = await post('/getEtag', { tockenid: u.token });
  assert.equal(no.json.code, -3);
  assert.equal((await post('/canOpenCloud', { tockenid: u.token })).json.code, -3);

  const [code] = app.svc.makeCodes({ kind: 'vip', days: 30 });
  const r = await post('/redeem', { tockenid: u.token, code: code.toLowerCase().replace(/-/g, ' ') });
  assert.equal(r.json.code, 0, JSON.stringify(r.json));
  const until = r.json.data.until;
  assert.ok(until > Date.now() + 29 * 86400000 && until < Date.now() + 31 * 86400000);
  assert.equal((await post('/canOpenCloud', { tockenid: u.token })).json.code, 0);
  const info = await post('/getUserInfo', { tockenid: u.token });
  assert.equal(info.json.data.isvip, true);
  // second use of the same code fails
  const again = await post('/redeem', { tockenid: u.token, code });
  assert.notEqual(again.json.code, 0);
  // a second code extends from the current expiry
  const [code2] = app.svc.makeCodes({ kind: 'vip', days: 10 });
  const r2 = await post('/paynew', { tockenid: u.token, vipType: code2, paymentType: 'code' });
  assert.equal(r2.json.code, 0);
  assert.equal(r2.json.data, 'ok');
  const row = app.svc.getUser(u.id);
  assert.ok(row.vip_until > until + 9 * 86400000);
  // codes are stored hashed
  const stored = app.db.prepare('SELECT code_hash FROM codes').all().map((x) => x.code_hash);
  assert.ok(!stored.some((h) => code.includes(h)));
  // paynew without a code is "not supported"
  const np = await post('/paynew', { tockenid: u.token, vipType: '1', paymentType: 'apple' });
  assert.equal(np.json.errorMsg, '暂不支持');
});

test('expired membership closes the cloud again', async () => {
  const u = await newUser('erin', { days: 1 });
  assert.equal((await post('/getEtag', { tockenid: u.token })).json.code, -5); // member, nothing stored yet
  app.db.prepare('UPDATE users SET vip_until = ? WHERE id = ?').run(Date.now() - 1000, u.id);
  assert.equal((await post('/getEtag', { tockenid: u.token })).json.code, -3);
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.data.isvip, false);
});

test('cloud sync: items, md5, lists and etag/update-url flow', async () => {
  const u = await newUser('frank', { days: 30 });
  const t = { tockenid: u.token, appid: u.appid };
  assert.equal((await post('/getItemJson', { ...t, item: 'tts_engines' })).json.code, -5);
  const body = JSON.stringify([{ name: '引擎', id: 1 }]);
  const up = await multipart('/setItemJsonFile', { ...t, item: 'tts_engines', t: Date.now() }, {}, 'file', 'tts.json', body);
  assert.equal(up.code, 0, JSON.stringify(up));
  const got = await post('/getItemJson', { ...t, item: 'tts_engines' });
  assert.equal(got.json.data, body);
  assert.equal((await post('/getItemMd5', { ...t, item: 'tts_engines' })).json.data, md5(body));

  // a list kind (bookshelf) uploaded under its item name
  assert.equal((await post('/getEtag', t)).json.code, -5);
  assert.equal((await post('/getBooks', t)).json.code, -5);
  const books = JSON.stringify([{ bookUrl: 'u1', name: 'A' }, { bookUrl: 'u2', name: 'B' }]);
  assert.equal((await multipart('/setItemJsonFile', { ...t, item: 'books' }, {}, 'file', 'b.json', books)).code, 0);
  const etag = (await post('/getEtag', t)).json.data;
  assert.equal(etag, md5(books));
  assert.equal((await post('/getBooks', t)).json.data, books);
  assert.equal((await post('/getBookUpdateurl', { ...t, etag })).json.data, ''); // up to date
  assert.equal((await post('/getBookUpdateurl', { ...t, etag: 'old' })).json.data, etag); // newer exists
  // item names are validated
  assert.notEqual((await post('/getItemJson', { ...t, item: '../etc/passwd' })).json.code, 0);
  // data of one user is not visible to another
  const other = await newUser('gina', { days: 30 });
  assert.equal((await post('/getBooks', { tockenid: other.token })).json.code, -5);
});

test('devices: list, remove, token dies with the device', async () => {
  const u = await newUser('hank');
  const second = await post('/login', { username: 'hank', password: 'secret-pw', platform: 'ios', model: 'iPad', appid: 'ipad-1' });
  const tok2 = second.json.data.vip;
  const list = await post('/getloginDevice', { tockenid: u.token });
  assert.equal(list.json.data.length, 2);
  assert.deepEqual(list.json.data.map((d) => d.appid).sort(), ['dev-hank', 'ipad-1']);
  assert.equal((await post('/removeDevice', { tockenid: u.token, appid: 'ipad-1' })).json.code, 0);
  assert.equal((await post('/getUserInfo', { tockenid: tok2 })).json.code, -2);
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.code, 0);
  // same appid logging in again replaces its token
  const again = await post('/login', { username: 'hank', password: 'secret-pw', appid: 'dev-hank' });
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.code, -2);
  assert.equal((await post('/getUserInfo', { tockenid: again.json.data.vip })).json.code, 0);
});

test('logout, nickname, password change', async () => {
  const u = await newUser('ivy');
  assert.equal((await post('/updateNickname', { tockenid: u.token, nickname: '常春藤' })).json.code, 0);
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.data.nickname, '常春藤');
  assert.notEqual((await post('/changePassword', { tockenid: u.token, oldpassword: 'bad', newpassword: 'new-secret' })).json.code, 0);
  assert.equal((await post('/changePassword', { tockenid: u.token, oldpassword: 'secret-pw', newpassword: 'new-secret' })).json.code, 0);
  // password change logs every device out
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.code, -2);
  const l = await post('/login', { username: 'ivy', password: 'new-secret', appid: 'a' });
  assert.equal(l.json.code, 0);
  assert.equal((await post('/logout', { tockenid: l.json.data.vip })).json.code, 0);
  assert.equal((await post('/getUserInfo', { tockenid: l.json.data.vip })).json.code, -2);
});

test('avatar upload and image dedupe', async () => {
  const u = await newUser('jack');
  const r = await multipart('/updateAvatar', { tockenid: u.token }, {}, 'file', 'a.png', PNG);
  assert.equal(r.code, 0, JSON.stringify(r));
  const res = await fetch(r.data.avatar_url);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'image/png');
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), PNG);
  assert.equal((await post('/getUserInfo', { tockenid: u.token })).json.data.avatar_url, r.data.avatar_url);
  const bad = await multipart('/updateAvatar', { tockenid: u.token }, {}, 'file', 'a.txt', 'not an image');
  assert.notEqual(bad.code, 0);
  const sum = md5(PNG);
  assert.equal((await post('/hasimg', { tockenid: u.token, md5: sum })).json.code, -5);
  const up = await multipart('/imgupload', { md5: sum, tockenid: u.token }, {}, 'file', 'p.png', PNG);
  assert.equal(up.code, 0);
  assert.equal((await post('/hasimg', { tockenid: u.token, md5: sum })).json.code, 0);
});

test('theme plaza contract', async () => {
  const dir = path.join(tmp, 'src');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'a.zip'), 'PK-fake');
  const cfg = app.cfg;
  admin(['add-category', '暗色'], { cfg: { ...cfg, dbPath: ':memory:' }, out: () => {} }); // separate DB: must not affect ours
  app.db.prepare('INSERT INTO categories(name) VALUES (?)').run('暗色');
  const out = [];
  // use the app's own database through the same path-less handle: insert like the CLI does
  const now = new Date().toISOString();
  for (let i = 1; i <= 3; i++) {
    app.db.prepare('INSERT INTO themes(id,name,category_id,zip_path,created_at,updated_at) VALUES (?,?,?,?,?,?)').run(`t${i}`, `主题${i}`, 1, `/public/files/a.zip`, now, now);
  }
  fs.mkdirSync(path.join(tmp, 'themes', 'files'), { recursive: true });
  fs.writeFileSync(path.join(tmp, 'themes', 'files', 'a.zip'), 'PK-fake');
  const cats = await (await fetch(base + '/public/categories')).json();
  assert.equal(cats.code, 200);
  assert.deepEqual(cats.data, [{ id: 1, name: '暗色' }]);
  const page1 = await (await fetch(base + '/public/themes?page=1&limit=2&category_id=1')).json();
  assert.equal(page1.code, 200);
  assert.equal(page1.data.items.length, 2);
  assert.deepEqual([page1.data.total, page1.data.page, page1.data.limit, page1.data.max_page], [3, 1, 2, 2]);
  const t = page1.data.items[0];
  for (const k of ['id', 'name', 'description', 'category_id', 'category', 'zip_path', 'layout_path', 'image_path', 'version', 'author', 'theme_mode', 'created_at', 'updated_at']) assert.ok(k in t, k);
  assert.equal(t.category.name, '暗色');
  const one = await (await fetch(base + '/public/themes/t2')).json();
  assert.equal(one.data.id, 't2');
  assert.equal((await (await fetch(base + '/public/themes/zzz')).json()).code, 404);
  const file = await fetch(base + '/public/files/a.zip');
  assert.equal(file.status, 200);
  assert.equal((await fetch(base + '/public/files/..%2f..%2fqread.db')).status, 404);
  void out;
});

test('会员中心 page is served with a strict CSP and no inline script', async () => {
  const r = await fetch(base + '/vip?tockenid=abc');
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-security-policy'), /script-src 'self'/);
  const html = await r.text();
  assert.ok(html.includes('会员中心') && html.includes('/vip.js'));
  assert.ok(!/<script>[^<]/.test(html));
  const js = await fetch(base + '/vip.js');
  assert.match(js.headers.get('content-type'), /javascript/);
});

test('forgetPassword is disabled without mail; registration can be closed', async () => {
  assert.notEqual((await post('/forgetPassword', { email: 'x@example.com' })).json.code, 0);
  const closed = createApp({ dbPath: ':memory:', dataDir: tmp, register: 'closed', log: false });
  const [inv] = closed.svc.makeCodes({ kind: 'invite' });
  const r = await (async () => {
    try {
      closed.svc.register({ username: 'zed', email: 'z@example.com', password: 'secret-pw', code: inv });
      return 'registered';
    } catch (e) {
      return e.msg;
    }
  })();
  assert.match(r, /不开放注册/);
  await closed.close();
});

test('free accounts are limited to 2 backup devices when cloud is open to everyone', async () => {
  const open = createApp({ dbPath: ':memory:', dataDir: tmp, cloudNeedsVip: false, log: false });
  await new Promise((r) => open.server.listen(0, '127.0.0.1', r));
  const b = `http://127.0.0.1:${open.server.address().port}`;
  const P = async (p, body) => (await fetch(b + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })).json();
  open.svc.createUser({ username: 'kate', email: 'k@example.com', password: 'secret-pw' });
  const logins = [];
  for (const id of ['d1', 'd2', 'd3']) logins.push((await P('/login', { username: 'kate', password: 'secret-pw', appid: id })).data.vip);
  assert.equal((await P('/openAuto', { tockenid: logins[0], appid: 'd1', st: 0 })).code, 0);
  assert.equal((await P('/openAuto', { tockenid: logins[1], appid: 'd2', st: 0 })).code, 0);
  const third = await P('/openAuto', { tockenid: logins[2], appid: 'd3', st: 0 });
  assert.notEqual(third.code, 0);
  assert.match(third.errorMsg, /最多只能备份 2/);
  assert.equal((await P('/getAutoDevice', { tockenid: logins[0] })).data.length, 2);
  assert.equal((await P('/removeAutoDevice', { tockenid: logins[0], appid: 'd1' })).code, 0);
  assert.equal((await P('/openAuto', { tockenid: logins[2], appid: 'd3', st: 0 })).code, 0);
  await open.close();
});

test('admin CLI: users, grants, codes', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-admin-'));
  const cfg = loadConfig({ dataDir: dir });
  const lines = [];
  const out = (s) => lines.push(s);
  admin(['create-user', 'root', 'root@example.com', '--password', 'pw-123456', '--days', '5'], { cfg, out });
  admin(['grant', 'root', '10'], { cfg, out });
  admin(['make-codes', 'vip', '30', '--count', '2', '--note', 'test'], { cfg, out });
  admin(['make-codes', 'invite', '--count', '1'], { cfg, out });
  admin(['list-users'], { cfg, out });
  admin(['list-codes', '--unused'], { cfg, out });
  assert.match(lines[0], /"username":"root"/);
  assert.match(lines[1], /vip until \d{4}-\d{2}-\d{2}/);
  assert.equal(lines.filter((l) => /^QR-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$/.test(l)).length, 2);
  assert.equal(lines.filter((l) => /^\d{6}$/.test(l)).length, 1);
  assert.ok(lines.some((l) => l.startsWith('1\troot\t') && /vip:\d{4}/.test(l)));
  assert.equal(lines.filter((l) => /unused/.test(l)).length, 3);
  fs.rmSync(dir, { recursive: true, force: true });
});
