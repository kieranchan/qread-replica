// The WebDAV book repository (/dav): Basic auth with the password or a session token, the methods the app's client uses, path
// safety, size and quota limits.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/server.mjs';

let app, base, tmp;

async function post(p, body) {
  const r = await fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return r.json();
}
const basic = (u, p) => 'Basic ' + Buffer.from(`${u}:${p}`).toString('base64');
const dav = (method, p, auth, { body, headers = {} } = {}) =>
  fetch(base + p, { method, headers: { ...(auth ? { Authorization: auth } : {}), ...headers }, body });

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-dav-'));
  app = createApp({ dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false, davMaxFileBytes: 1024, davQuotaBytes: 2500 });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
  app.cfg.baseUrl = base;
});
after(async () => {
  await app.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('dav: auth, collections, files, listing, move, limits', async () => {
  const [inv] = app.svc.makeCodes({ kind: 'invite', count: 1, validDays: 1 });
  assert.equal((await post('/register', { username: 'davuser', email: 'dav@example.com', password: 'secret-pw', code: inv })).code, 0);
  const login = await post('/login', { username: 'davuser', password: 'secret-pw', platform: 'ios', model: 'iPhone', appid: 'dav-1' });
  const token = login.data.id;
  const pw = basic('davuser', 'secret-pw');
  const tok = basic('davuser', token);

  // OPTIONS needs no auth (the client pings first); everything else does
  assert.equal((await dav('OPTIONS', '/dav/')).status, 200);
  const noAuth = await dav('PROPFIND', '/dav/');
  assert.equal(noAuth.status, 401);
  assert.match(noAuth.headers.get('www-authenticate'), /Basic/);
  assert.equal((await dav('PROPFIND', '/dav/', basic('davuser', 'wrong'))).status, 401);
  assert.equal((await dav('PROPFIND', '/dav/', basic('nobody', 'secret-pw'))).status, 401);

  // root listing (empty), collection, file
  const root = await dav('PROPFIND', '/dav/', pw, { headers: { Depth: '1' } });
  assert.equal(root.status, 207);
  assert.match(await root.text(), /<D:href>\/dav\/<\/D:href>/);
  assert.equal((await dav('MKCOL', '/dav/books', tok)).status, 201);
  assert.equal((await dav('MKCOL', '/dav/books', tok)).status, 405); // exists
  assert.equal((await dav('MKCOL', '/dav/no/parent', tok)).status, 409);
  assert.equal((await dav('PUT', '/dav/books/a.txt', tok, { body: 'hello' })).status, 201);
  assert.equal((await dav('PUT', '/dav/books/a.txt', pw, { body: 'hello world' })).status, 204); // overwrite
  const zh = encodeURIComponent('斩神.epub');
  assert.equal((await dav('PUT', `/dav/books/${zh}`, tok, { body: Buffer.alloc(300, 1) })).status, 201);
  const list = await dav('PROPFIND', '/dav/books/', tok, { headers: { Depth: '1' } });
  assert.equal(list.status, 207);
  const xml = await list.text();
  assert.match(xml, /<D:href>\/dav\/books\/<\/D:href>/);
  assert.match(xml, /<D:href>\/dav\/books\/a\.txt<\/D:href>[\s\S]*<D:getcontentlength>11<\/D:getcontentlength>/);
  assert.ok(xml.includes(`/dav/books/${zh}`));
  assert.match(xml, /<D:displayname>斩神\.epub<\/D:displayname>/);
  const one = await dav('PROPFIND', '/dav/books/a.txt', tok, { headers: { Depth: '0' } });
  assert.equal((await one.text()).match(/<D:response>/g).length, 1);
  // get / head
  const got = await dav('GET', '/dav/books/a.txt', tok);
  assert.equal(got.status, 200);
  assert.equal(await got.text(), 'hello world');
  const head = await dav('HEAD', '/dav/books/a.txt', tok);
  assert.equal(head.status, 200);
  assert.equal(head.headers.get('content-length'), '11');
  assert.equal((await dav('GET', '/dav/books/missing.txt', tok)).status, 404);
  assert.equal((await dav('PROPFIND', '/dav/nothing', tok)).status, 404);
  // move / delete
  assert.equal((await dav('MOVE', '/dav/books/a.txt', tok, { headers: { Destination: `${base}/dav/books/b.txt` } })).status, 201);
  assert.equal((await dav('GET', '/dav/books/a.txt', tok)).status, 404);
  assert.equal(await (await dav('GET', '/dav/books/b.txt', tok)).text(), 'hello world');
  assert.equal((await dav('DELETE', '/dav/books/b.txt', tok)).status, 204);
  assert.equal((await dav('DELETE', '/dav/books/b.txt', tok)).status, 404);
  assert.equal((await dav('DELETE', '/dav/', tok)).status, 403);
  // path safety and limits
  assert.equal((await dav('PUT', '/dav/..%2Fescape.txt', tok, { body: 'x' })).status, 400);
  assert.ok([400, 404].includes((await dav('GET', '/dav/%2e%2e/%2e%2e/etc/passwd', tok)).status)); // dot segments are normalised away before the handler
  assert.equal((await dav('PUT', '/dav/books/big.txt', tok, { body: Buffer.alloc(2000, 2) })).status, 413);
  assert.equal((await dav('PUT', '/dav/books/q1.txt', tok, { body: Buffer.alloc(1000, 3) })).status, 201);
  assert.equal((await dav('PUT', '/dav/books/q2.txt', tok, { body: Buffer.alloc(1000, 3) })).status, 201);
  assert.equal((await dav('PUT', '/dav/books/q3.txt', tok, { body: Buffer.alloc(1000, 3) })).status, 507); // 300 + 2000 + 1000 > 2500
  // the files live under the user's own folder; another user sees nothing
  assert.ok(fs.existsSync(path.join(tmp, 'dav', String(login.data.userId), 'books', 'q1.txt')));
  const [inv2] = app.svc.makeCodes({ kind: 'invite', count: 1, validDays: 1 });
  assert.equal((await post('/register', { username: 'davother', email: 'dav2@example.com', password: 'secret-pw', code: inv2 })).code, 0);
  assert.equal((await dav('PROPFIND', '/dav/books/', basic('davother', 'secret-pw'))).status, 404);
  // a dead token no longer opens the store
  assert.equal((await post('/logout', { tockenid: token })).code, 0);
  assert.equal((await dav('PROPFIND', '/dav/', tok)).status, 401);
  assert.equal((await dav('PROPFIND', '/dav/', pw)).status, 207);
});
