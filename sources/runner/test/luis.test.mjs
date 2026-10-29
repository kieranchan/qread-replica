// Closed loop of the 路易斯 platform: the 路易斯聚合 page (sources/luis) running in headless Chrome against the qread
// server started in-process, with a test adapter and the members-only 路易斯书库.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Runner, decode } from '../run.mjs';
import { findChrome } from '../chrome.mjs';
import { build } from '../../build.mjs';
import { createApp } from '../../../server/src/server.mjs';
import { libraryAdapter } from '../../../server/src/luis/adapters/library.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const chrome = findChrome();

const demo = {
  name: '演示',
  tabs: ['小说'],
  tier: 'free',
  search: async (key) => (key === '演示' ? [{ id: 'd1', name: '演示之书', author: '甲', intro: '简介', status: '连载中', latestChapter: '第二章', tags: ['玄幻'] }] : []),
  detail: async () => ({ name: '演示之书', author: '甲', intro: '详情简介', status: '连载中', latestChapter: '第二章' }),
  catalog: async () => [{ id: 'c1', title: '第一章' }, { id: 'c2', title: '第二章' }],
  content: async (id) => ({ title: id === 'c1' ? '第一章' : '第二章', content: (id === 'c1' ? '第一章' : '第二章') + '\n正文第一段\n正文第二段' }),
  discover: async () => [{ title: '榜单', key: 'top', width: 1 }],
  discoverList: async (key, page) => (page === 1 ? [{ id: 'd1', name: '演示之书', author: '甲' }] : []),
};

let app, base, tmp, runner, lib;

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qyd-luis-'));
  app = createApp({
    dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false,
    luisAdapters: (db) => {
      lib = libraryAdapter(db);
      return [demo, lib];
    },
  });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
  app.cfg.baseUrl = base;
  lib.add({ name: '会员之书', author: '乙', intro: '书库', text: '第一章 甲\n书库正文\n第二章 乙\n更多正文' });
  const user = app.svc.createUser({ username: 'tester', email: 'tester@example.com', password: 'secret-pw', days: 30 });
  const token = app.svc.issueToken(user, { appid: 'luis:test', platform: 'luis', model: 'test' });
  const { html } = build('luis');
  const page = path.join(tmp, 'luis.html');
  fs.writeFileSync(page, html);
  if (chrome) {
    runner = await Runner.start({
      page,
      base: 'https://qread.forfine.me/tsy/luis',
      stateDir: path.join(tmp, 'state'),
      quiet: true,
      log: () => {},
      cacheSeed: { server: `${base}/luis` },
      cookies: [{ url: base, text: `qttoken=${token}; deviceId=test-device` }],
    });
  }
});
after(async () => {
  await runner?.close();
  await app?.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('discovery page: drop-downs from /sources/config, account entry, platform lists', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  const finds = decode(await runner.getfinds());
  const titles = finds.map((k) => k.title);
  assert.deepEqual(titles.slice(0, 5), ['线路', '类型', '频道', '平台', '搜索范围']);
  assert.deepEqual(finds[3].chars, ['演示', '路易斯书库']);
  assert.deepEqual(finds[4].chars, ['全部', '演示', '路易斯书库']);
  assert.equal(finds[1].chars.length, 1);
  const account = finds.find((k) => k.title === '账户中心');
  assert.equal(account.type, 1);
  assert.equal(account.url, `${base}/luis/user`);
  const top = finds.find((k) => k.title === '榜单');
  assert.match(top.url, /\/luis\/get_discover\?source=/);
  const list = decode(await runner.find(top.url, 1));
  assert.equal(list[0].name, '演示之书');
});

test('search -> info -> chapter -> content against the in-process platform', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  const books = decode(await runner.search('演示', 1, 'search'));
  assert.equal(books.length, 1, JSON.stringify(books));
  assert.equal(books[0].name, '演示之书');
  assert.equal(books[0].latestChapterTitle, '演示:第二章');
  assert.match(books[0].bookUrl, /\/luis\/detail\?book_id=/);
  const info = decode(await runner.info(books[0].bookUrl));
  assert.equal(info.author, '甲');
  assert.match(info.intro, /^@html:/);
  assert.match(info.intro, /tester（已登录）/);
  const chapters = decode(await runner.chapter(info.tocUrl, books[0].bookUrl));
  assert.deepEqual(chapters.map((c) => c.name), ['第一章', '第二章']);
  const text = await runner.content(chapters[0].chapterId, books[0].bookUrl, 0);
  assert.equal(text, '正文第一段\n正文第二段');
  assert.equal(runner.texts.filter((t) => t.type === 3).length, 1);
});

test('members-only platform through the page, help and login url', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  runner.cache.set('sources', '路易斯书库');
  const books = decode(await runner.search('会员', 1, 'search'));
  assert.equal(books.length, 1);
  const info = decode(await runner.info(books[0].bookUrl));
  const chapters = decode(await runner.chapter(info.tocUrl, books[0].bookUrl));
  assert.equal(chapters.length, 2);
  assert.equal(await runner.content(chapters[1].chapterId, books[0].bookUrl, 1), '更多正文');
  runner.cache.set('sources', '全部');
  assert.match(await runner.gethelp(), /路易斯聚合[\s\S]*账户：tester[\s\S]*会员平台：路易斯书库/);
  assert.equal(await runner.getloginurl(), `${base}/luis/login?source_client=qyd`);
  // without the cookie the members-only platform is refused with the platform's message
  runner.jar.remove(base);
  runner.cache.remove('qttoken');
  runner.cache.set('sources', '路易斯书库');
  assert.deepEqual(decode(await runner.search('会员', 1, 'search')), []);
  assert.match(runner.toasts.at(-1), /需要/);
});
