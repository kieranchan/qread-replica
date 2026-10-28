import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/server.mjs';
import { run as admin } from '../src/admin.mjs';

let app, base, tmp;
const PAGE = '<!doctype html><html><body></body><script>async function search(k,p){return "[]"} async function info(u){return "{}"} async function chapter(t,b){return "[]"} async function content(u,b,i){return ""}</script></html>';

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-tsy-'));
  app = createApp({ dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
  app.cfg.baseUrl = base;
});
after(async () => {
  await app.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('hosted 时光源 pages: set-source, list-sources, GET /tsy/<name>.html', async () => {
  assert.equal((await fetch(base + '/tsy/langge.html')).status, 404);
  const file = path.join(tmp, 'page.html');
  fs.writeFileSync(file, PAGE);
  const lines = [];
  admin(['set-source', 'langge', file], { cfg: app.cfg, out: (s) => lines.push(s) });
  assert.equal(lines[0], base + '/tsy/langge.html');
  const r = await fetch(base + '/tsy/langge.html');
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type'), /text\/html/);
  assert.equal(await r.text(), PAGE);
  assert.equal((await fetch(base + '/tsy/langge')).status, 200);
  assert.equal((await fetch(base + '/tsy/..%2Fqread.db')).status, 404);
  assert.equal((await fetch(base + '/tsy/other.html')).status, 404);
  lines.length = 0;
  admin(['list-sources'], { cfg: app.cfg, out: (s) => lines.push(s) });
  assert.equal(lines[0], base + '/tsy/langge.html');
  fs.writeFileSync(file, '<html>not a source</html>');
  assert.throws(() => admin(['set-source', 'x', file], { cfg: app.cfg, out: () => {} }), /not a 时光源 page/);
  assert.throws(() => admin(['set-source', '../x', file], { cfg: app.cfg, out: () => {} }), /set-source/);
});
