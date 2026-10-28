// check_update (the app's 检查更新 / main-page update reminder) answered from the release set with `admin set-update`.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/server.mjs';
import { run as admin } from '../src/admin.mjs';
import { loadConfig } from '../src/config.mjs';

let app, base, tmp;

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-update-'));
  app = createApp({ dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});
after(async () => {
  await app.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

const check = async (q) => (await fetch(`${base}/check_update?${new URLSearchParams({ t: String(Date.now()), ...q })}`)).json();

function setUpdate(obj, extra = []) {
  const lines = [];
  const file = path.join(tmp, 'rel.json');
  if (obj !== undefined) fs.writeFileSync(file, typeof obj === 'string' ? obj : JSON.stringify(obj));
  admin(obj === undefined ? ['set-update', ...extra] : ['set-update', file, ...extra], { cfg: loadConfig({ dataDir: tmp }), out: (s) => lines.push(s) });
  return lines;
}

test('no release set: code != 0 (no update)', async () => {
  const r = await check({ platform: 'ios', version: '1' });
  assert.notEqual(r.code, 0);
});

test('set-update: newer build -> code 0 with updateUrl / description; same or newer client build -> no update', async () => {
  const out = setUpdate({ version: '1.0.1', build: 5, notes: '修复若干问题\n新增功能', url: 'https://example.com/newread-5.ipa', platform: 'ios' });
  assert.match(out[0], /update set: 1\.0\.1 build 5 for ios/);
  const r = await check({ platform: 'ios', version: '4' });
  assert.deepEqual(r, { code: 0, updateUrl: 'https://example.com/newread-5.ipa', description: '修复若干问题\n新增功能', version: '1.0.1', build: 5 });
  assert.notEqual((await check({ platform: 'ios', version: '5' })).code, 0);
  assert.notEqual((await check({ platform: 'ios', version: '6' })).code, 0);
  assert.notEqual((await check({ platform: 'android', version: '1' })).code, 0, 'release is for ios only');
  // POST works too (the app's http helper)
  const p = await (await fetch(`${base}/check_update?platform=ios&version=2&t=1`, { method: 'POST' })).json();
  assert.equal(p.code, 0);
  // a release without platform applies to every platform; show-update prints it
  setUpdate({ version: '1.0.2', build: 6, url: 'https://example.com/6' });
  assert.equal((await check({ platform: 'android', version: '1' })).code, 0);
  const shown = [];
  admin(['show-update'], { cfg: loadConfig({ dataDir: tmp }), out: (s) => shown.push(s) });
  assert.equal(JSON.parse(shown[0]).build, 6);
});

test('set-update validates the file; --clear removes the release', async () => {
  assert.throws(() => setUpdate({ version: '1', build: 0, url: 'https://x' }), /build/);
  assert.throws(() => setUpdate({ version: '1', build: 3, url: 'ftp://x' }), /url/);
  assert.throws(() => setUpdate('not json'));
  assert.equal((await check({ platform: 'ios', version: '1' })).code, 0, 'a rejected file leaves the old release');
  const out = setUpdate(undefined, ['--clear']);
  assert.match(out[0], /cleared/);
  assert.notEqual((await check({ platform: 'ios', version: '1' })).code, 0);
});
