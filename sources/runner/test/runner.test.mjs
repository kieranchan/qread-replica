import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Runner, decode } from '../run.mjs';
import { findChrome } from '../chrome.mjs';
import { gbkUrlEncode, CookieJar, decodeBody } from '../bridge.mjs';
import { startFixture, BOOKS } from './fixture.mjs';

const chrome = findChrome();
let site, runner, tmp;

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qyd-runner-test-'));
  site = await startFixture();
  if (chrome) runner = await Runner.start({ page: `${site.base}/source.html`, stateDir: tmp, quiet: true, log: () => {} });
});
after(async () => {
  await runner?.close();
  await site?.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('gbk url encoding matches the GBK bytes', () => {
  assert.equal(gbkUrlEncode('斗破 a'), '%B6%B7%C6%C6%20a');
  assert.equal(gbkUrlEncode('测试'), '%B2%E2%CA%D4');
});

test('cookie jar: domains, replace, one cookie', () => {
  const jar = new CookieJar('');
  jar.store('https://a.example.com/x', ['s=1; Path=/; Domain=.example.com', 'h=2; HttpOnly']);
  assert.equal(jar.header('https://b.example.com/'), 's=1');
  assert.equal(jar.header('https://a.example.com/'), 's=1; h=2');
  jar.setOne('https://a.example.com', 'h', '3');
  assert.equal(jar.map('https://a.example.com').h, '3');
  jar.set('https://a.example.com', 'x=9; y=8');
  assert.deepEqual(jar.map('https://a.example.com'), { s: '1', x: '9', y: '8' });
  jar.remove('https://a.example.com');
  assert.equal(jar.header('https://a.example.com/'), 's=1');
});

test('body decoding follows the content type and the meta charset', () => {
  const gbk = Buffer.from([0xb2, 0xe2, 0xca, 0xd4]);
  assert.equal(decodeBody(gbk, 'text/html; charset=gbk'), '测试');
  const meta = Buffer.concat([Buffer.from('<html><head><meta charset="gb2312"></head><body>'), gbk]);
  assert.equal(decodeBody(meta, 'text/html'), '<html><head><meta charset="gb2312"></head><body>测试');
  assert.equal(decodeBody(Buffer.from('é', 'utf8'), undefined), 'é');
});

test('the page reports ready and the whole flow runs', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  await runner.waitReady();
  assert.equal(runner.isCookieJar, true);
  const books = decode(await runner.search('测试', 1, 'search'));
  assert.equal(books.length, 2, JSON.stringify(books));
  assert.equal(books[0].name, BOOKS[0].name);
  assert.equal(books[0].kind, '测试,search');
  assert.equal(runner.cache.get('lastKey'), '测试');
  assert.equal(runner.texts.length, 1);
  assert.equal(runner.texts[0].type, 0);

  const info = decode(await runner.info(books[0].bookUrl));
  assert.equal(info.author, '作者甲');
  assert.match(info.tocUrl, /\/toc\/1$/);
  assert.equal(info.latestChapterTitle, '第三章 结束');
  assert.equal(runner.jar.map(site.base).visited, 'yes');

  const chapters = decode(await runner.chapter(info.tocUrl, books[0].bookUrl));
  assert.equal(chapters.length, 3);
  assert.equal(chapters[2].index, 2);

  const text = await runner.content(chapters[1].chapterId, books[0].bookUrl, 1);
  assert.match(text, /<p>第一段 visited=yes<\/p>/);
  assert.match(text, /cookie=yes index=1/);
});

test('explore entries, actions and discovery lists', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  const finds = decode(await runner.getfinds());
  assert.equal(finds.length, 3);
  assert.equal(finds[0].type, 2);
  assert.deepEqual(finds[0].chars, ['最新', '最热']);
  assert.equal(finds[2].width, 3);
  runner.cache.set('排序', '最热');
  assert.equal(await runner.runJs(finds[0].action), 'sorted');
  assert.equal(runner.cache.get('sort'), '最热');
  assert.equal(runner.state.refreshExplore, 1);
  const list = decode(await runner.find(finds[1].url, 2));
  assert.equal(list.length, 2);
});

test('login form, help, events', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  const form = decode(await runner.getloginurl());
  assert.equal(form[1].type, 'password');
  runner.cache.set('LoginInfo', '{"用户名":"u"}');
  assert.equal(await runner.login(), 'login:{"用户名":"u"}');
  assert.equal(await runner.gethelp(), '@html:<b>help</b>');
  assert.equal(await runner.callbackjs('clickBookName', '{}'), 'true');
  assert.equal(await runner.callbackjs('other', '{}'), 'false');
});

test('webview handler: js value after the page settled, inline html, url regex', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  assert.equal(await runner.call('webtest()', 30000), 'dyn:ready');
  assert.equal(await runner.call('webhtml()', 30000), 'inline');
  assert.match(await runner.call('webregex()', 30000), /\/asset\.js$/);
});

test('a page function that throws answers "" like the app', { skip: !chrome && 'no Chrome/Edge installed' }, async () => {
  assert.equal(await runner.call('noSuchFunction()', 5000), '');
});
