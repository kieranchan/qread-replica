import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/server.mjs';
import { run as admin } from '../src/admin.mjs';
import { b64u } from '../src/luis/engine.mjs';
import { libraryAdapter, splitChapters, decodeText } from '../src/luis/adapters/library.mjs';
import { wikisourceAdapter, chapterLinks, stripHtml } from '../src/luis/adapters/wikisource.mjs';

// ---- adapters of the test platform ----
const demo = {
  name: '演示',
  tabs: ['小说', '听书'],
  tier: 'free',
  search: async (key, page, tab) => (key.includes('无') || page > 1 ? [] : [{ id: 'd1', name: `演示之书·${tab}`, author: '甲', intro: '简介', cover: 'http://x/c.png', status: '连载中', latestChapter: '第二章', wordCount: '1.2万', tags: ['玄幻', '热血'], updatedAt: '2026-10-29' }]),
  detail: async (id) => (id === 'd1' ? { name: '演示之书', author: '甲', intro: '详情简介', status: '连载中', latestChapter: '第二章' } : null),
  catalog: async () => [{ id: 'c1', title: '第一章', wordCount: 100 }, { id: 'c2', title: '第二章', isPay: true }],
  content: async (id, tab) => (tab === '听书' ? 'https://media.example/x.mp3' : id === 'c1' ? { title: '第一章', content: '第一段\n第二段' } : null),
  discover: async () => [{ title: '榜单', key: 'top', width: 1 }, { title: '分组标题' }],
  discoverList: async (key, page) => (key === 'top' && page === 1 ? [{ id: 'd2', name: '榜单书', author: '乙' }] : []),
};
const vipOnly = { name: '登录站', tier: 'vip', search: async () => [{ id: 'v1', name: '登录才有' }], detail: async () => ({ name: '登录才有' }), catalog: async () => [], content: async () => '' };
const broken = { name: '坏站', tier: 'free', search: async () => { throw new Error('upstream down'); }, detail: async () => null, catalog: async () => [], content: async () => '' };

// a MediaWiki API stand-in for the 维基文库 adapter
const WIKITEXT = `{{header
 | title = 紅樓夢
 | override_author = [[author:曹雪芹|曹雪芹]]（前八十回）；[[author:高鶚|高鶚]]（後四十回）
 | section =
 | notes = 清代長篇小說，參見[[紅樓夢 (消歧義)]]。
 | edition = yes
}}
{{檢索|紅樓夢}}
* [[/第一回|第一回　甄士隱夢幻識通靈]]
* [[紅樓夢/第二回|第二回　賈夫人仙逝揚州城]]
* [[/第一回]]
{{:紅樓夢/第三回}}
`;
const VERSIONS = `{{versions
 | title = 水滸傳
 | override_author = {{多名作者|元末明初|施耐庵|著|元末明初|羅貫中|著}}
}}
* [[水滸傳 (100回本)|水滸傳]]，百回本
* [[水滸傳 (70回本)|水滸傳]]
* [[Category:小說]]
`;
const EDITION = `{{header|title=水滸傳 (100回本)}}
* [[/第001回|第一回 張天師祈禳瘟疫]]
* [[/第002回|第二回]]
`;
const VOLUMES = `{{header|title=聊齋志異|author=蒲松齡}}
* [[/作者自志|作者自志]]
* [[/第01卷|第一卷]] [[/第01卷| 考城隍]]
* [[/第02卷|第二卷]]
`;
const VOLUME1 = `{{header|title=聊齋志異/第01卷}}
* [[/考城隍]]
* [[/耳中人]]
`;
const VOLUME2 = `{{header|title=聊齋志異/第02卷}}
== 金世成 ==
金世成，長山人。
== 董生 ==
董生字遐思。
`;
const fakeWiki = async (url) => {
  const u = new URL(url);
  const p = Object.fromEntries(u.searchParams);
  let body;
  if (p.list === 'search') body = { query: { search: [{ title: '紅樓夢/第一回', snippet: '<span class="searchmatch">紅樓夢</span> 第一回' }, { title: '紅樓夢', snippet: '小說' }, { title: '後紅樓夢', snippet: '' }] } };
  else if (p.action === 'parse' && p.prop === 'wikitext') body = { parse: { title: p.page, wikitext: p.page === '紅樓夢' ? WIKITEXT : p.page === '水滸傳' ? VERSIONS : p.page.startsWith('水滸傳 (') ? EDITION : p.page === '聊齋志異' ? VOLUMES : p.page === '聊齋志異/第01卷' ? VOLUME1 : p.page === '聊齋志異/第02卷' ? VOLUME2 : '' } };
  else if (p.action === 'parse' && p.prop === 'sections') body = { parse: { title: p.page, sections: [{ toclevel: 1, index: '1', line: '金世成' }, { toclevel: 1, index: '2', line: '董生' }] } };
  else if (p.action === 'parse' && p.prop === 'text' && p.section) body = { parse: { title: p.page, text: `<div class="mw-parser-output"><h2><span class="mw-headline">${p.section === '1' ? '金世成' : '董生'}</span></h2><p>故事${p.section}正文。</p></div>` } };
  else if (p.action === 'parse' && p.prop === 'text') body = { parse: { title: p.page, text: '<div class="mw-parser-output"><table class="header"><tr><td>nav</td></tr></table><p>第一段文字。<sup class="reference">[1]</sup></p><p>第二段文字。</p><table><tr><td>table</td></tr></table></div>' } };
  else if (p.list === 'categorymembers') body = { query: { categorymembers: [{ title: '紅樓夢/第一回' }, { title: '紅樓夢' }, { title: '水滸傳' }] } };
  else body = { error: { code: 'unknown', info: 'unexpected call' } };
  return new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });
};

let app, base, tmp, lib;
const get = async (p, cookie = '') => {
  const r = await fetch(base + p, { headers: cookie ? { Cookie: cookie } : {} });
  return { status: r.status, json: await r.json(), headers: r.headers };
};
const post = async (p, body, cookie = '') => {
  const r = await fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) }, body: JSON.stringify(body) });
  return { status: r.status, json: await r.json(), headers: r.headers };
};

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-luis-'));
  app = createApp({
    dbPath: ':memory:', dataDir: tmp, port: 0, host: '127.0.0.1', baseUrl: 'http://127.0.0.1', log: false,
    luisAdapters: (db) => {
      lib = libraryAdapter(db);
      return [demo, vipOnly, broken, lib, wikisourceAdapter({ fetchImpl: fakeWiki })];
    },
  });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${app.server.address().port}`;
  app.cfg.baseUrl = base;
});
after(async () => {
  await app.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('sources/config lists the adapters by tier with their tabs', async () => {
  const { json } = await get('/luis/sources/config');
  assert.equal(json.code, 0);
  assert.deepEqual(json.data.free, ['演示', '坏站', '维基文库']);
  assert.deepEqual(json.data.vip, ['登录站']);
  assert.deepEqual(json.data.svip, ['路易斯书库']);
  assert.deepEqual(json.data.modes['演示'], ['小说', '听书']);
});

test('search without login: free platforms answer, locked ones are listed, failures are reported per source', async () => {
  const { json } = await get('/luis/search?title=' + encodeURIComponent('演示') + '&page=1&source=全部&tab=小说&disabled_sources=0');
  assert.equal(json.code, 0);
  assert.equal(json.cache, false);
  assert.deepEqual(json.disabled_sources, ['登录站', '路易斯书库']);
  const b = json.data.find((x) => x.source === '演示');
  assert.ok(b, JSON.stringify(json));
  assert.equal(b.book_name, '演示之书·小说');
  assert.equal(b64u.dec(b.book_id), 'd1');
  assert.equal(b.tags, '玄幻,热血');
  assert.equal(b.tab, '小说');
  const broke = json.source_time_cost.find((c) => c.source === '坏站');
  assert.match(broke.error, /upstream down/);
  const again = await get('/luis/search?title=' + encodeURIComponent('演示') + '&page=1&source=全部&tab=小说');
  assert.equal(again.json.cache, true);
  const only = await get('/luis/search?title=x&source=' + encodeURIComponent('登录站') + '&tab=小说');
  assert.equal(only.json.code, -3);
  assert.match(only.json.msg, /登录/);
  const none = await get('/luis/search?title=' + encodeURIComponent('无') + '&source=' + encodeURIComponent('演示') + '&tab=小说');
  assert.equal(none.json.code, 0);
  assert.equal(none.json.data.length, 0);
});

test('detail / catalog / content round trip, audio tab answers the media url, bad ids fail cleanly', async () => {
  const id = b64u.enc('d1');
  const d = await get(`/luis/detail?book_id=${id}&source=演示&tab=小说&variable=${encodeURIComponent('{"custom":"4"}')}`);
  assert.equal(d.json.code, 0);
  assert.equal(d.json.data.book_name, '演示之书');
  assert.equal(d.json.data.book_id, id);
  assert.equal(d.json.data.source, '演示');
  const c = await get(`/luis/catalog?book_id=${id}&source=演示&tab=小说`);
  assert.equal(c.json.data.length, 2);
  assert.equal(c.json.data[1].is_pay, true);
  assert.equal(b64u.dec(c.json.data[0].item_id), 'c1');
  const t = await get(`/luis/content?item_id=${c.json.data[0].item_id}&source=演示&tab=小说&version=5&tone_id=4`);
  assert.equal(t.json.code, 0);
  assert.equal(t.json.title, '第一章');
  assert.equal(t.json.content, '第一段\n第二段');
  const t2 = await get(`/luis/content?item_id=${c.json.data[0].item_id}&source=演示&tab=小说`);
  assert.equal(t2.json.cache, true);
  const audio = await get(`/luis/content?item_id=${c.json.data[0].item_id}&source=演示&tab=听书`);
  assert.equal(audio.json.content, 'https://media.example/x.mp3');
  const missing = await get(`/luis/content?item_id=${b64u.enc('nope')}&source=演示&tab=小说`);
  assert.notEqual(missing.json.code, 0);
  const unknown = await get(`/luis/detail?book_id=${id}&source=没有&tab=小说`);
  assert.equal(unknown.json.code, -1);
  const wrongTab = await get(`/luis/detail?book_id=${id}&source=演示&tab=漫画`);
  assert.equal(wrongTab.json.code, -1);
});

test('discovery entries and lists', async () => {
  const s = await get('/luis/discovestyle?source=演示&source_type=男频&tab=小说');
  assert.equal(s.json.code, 0);
  assert.equal(s.json.data[0].url, '');
  assert.match(s.json.data[0].title, /当前为: 演示/);
  const list = s.json.data.find((e) => e.title === '榜单');
  assert.match(list.url, /\/luis\/get_discover\?source=/);
  assert.equal(list.style.layout_flexBasisPercent, 0.45);
  assert.equal(s.json.data.find((e) => e.title === '分组标题').url, '');
  const page = await get(list.url.replace(base, '').replace('{{page}}', '1'));
  assert.equal(page.json.data[0].book_name, '榜单书');
  const empty = await get(list.url.replace(base, '').replace('{{page}}', '2'));
  assert.equal(empty.json.data.length, 0);
  const noDiscover = await get('/luis/discovestyle?source=坏站&tab=小说');
  assert.equal(noDiscover.json.data.length, 2);
});

test('login page sets the cookies, unlocks the login tier, membership unlocks svip; logout revokes', async () => {
  const page = await fetch(base + '/luis/login?source_client=qyd');
  assert.equal(page.status, 200);
  assert.match(await page.text(), /路易斯/);
  const u = app.svc.createUser({ username: 'reader', email: 'reader@example.com', password: 'secret-pw' });
  const bad = await post('/luis/login_api', { username: 'reader', password: 'wrong' });
  assert.equal(bad.json.code, -1);
  const ok = await post('/luis/login_api', { username: 'reader', password: 'secret-pw', client: 'qyd' });
  assert.equal(ok.json.code, 0, JSON.stringify(ok.json));
  const setCookies = ok.headers.getSetCookie();
  const qt = /qttoken=([^;]+)/.exec(setCookies.join('\n'))[1];
  const dev = /deviceId=([^;]+)/.exec(setCookies.join('\n'))[1];
  assert.ok(qt.length > 20);
  assert.ok(/HttpOnly/.test(setCookies.find((c) => c.startsWith('qttoken'))));
  const cookie = `qttoken=${qt}; deviceId=${dev}`;
  assert.equal((await get('/luis/get_avatar')).status, 400);
  const av = await get('/luis/get_avatar', cookie);
  assert.equal(av.status, 200);
  assert.equal(av.json.email, 'reader@example.com');
  const s1 = await get('/luis/search?title=x&source=全部&tab=小说', cookie);
  assert.ok(s1.json.data.some((b) => b.source === '登录站'));
  assert.deepEqual(s1.json.disabled_sources, ['路易斯书库']);
  const locked = await get(`/luis/detail?book_id=${b64u.enc('1')}&source=路易斯书库&tab=小说`, cookie);
  assert.equal(locked.json.code, -3);
  const me = await get('/luis/user_api', cookie);
  assert.equal(me.json.data.username, 'reader');
  assert.equal(me.json.data.isvip, false);
  assert.equal(me.json.data.qttoken, qt);
  assert.equal(me.json.data.sources.find((s) => s.name === '路易斯书库').available, false);
  app.svc.addDays(u.id, 30, 'admin', 'test');
  const me2 = await get('/luis/user_api', cookie);
  assert.equal(me2.json.data.isvip, true);
  assert.equal(me2.json.data.tier, 'svip');
  assert.equal(me2.json.data.sources.find((s) => s.name === '路易斯书库').available, true);
  // the same token also works as a query parameter (the page may pass it that way)
  const viaQuery = await get(`/luis/user_api?qttoken=${qt}`);
  assert.equal(viaQuery.json.code, 0);
  const out = await post('/luis/logout', {}, cookie);
  assert.equal(out.json.code, 0);
  assert.equal((await get('/luis/user_api', cookie)).json.code, -2);
  assert.equal((await get('/luis/user_api')).json.code, -2);
});

test('路易斯书库: books from text, members only, through the API', async () => {
  const r = lib.add({ name: '测试长篇', author: '丙', intro: '书库简介', tags: '测试', text: '前言太短\n第一章 开端\n　　第一段。\n第二段。\n\n第二章 发展\n内容二\n第三章 结局\n内容三\n' });
  assert.equal(r.chapters, 3);
  const u = app.svc.createUser({ username: 'member', email: 'member@example.com', password: 'secret-pw', days: 10 });
  const login = await post('/luis/login_api', { username: 'member', password: 'secret-pw' });
  const cookie = `qttoken=${/qttoken=([^;]+)/.exec(login.headers.getSetCookie().join('\n'))[1]}`;
  const s = await get('/luis/search?title=' + encodeURIComponent('长篇') + '&source=路易斯书库&tab=小说', cookie);
  assert.equal(s.json.code, 0, JSON.stringify(s.json));
  assert.equal(s.json.data.length, 1);
  assert.equal(s.json.data[0].last_chapter_title, '第三章 结局');
  const bookId = s.json.data[0].book_id;
  const d = await get(`/luis/detail?book_id=${bookId}&source=路易斯书库&tab=小说`, cookie);
  assert.equal(d.json.data.author, '丙');
  const c = await get(`/luis/catalog?book_id=${bookId}&source=路易斯书库&tab=小说`, cookie);
  assert.deepEqual(c.json.data.map((x) => x.title), ['第一章 开端', '第二章 发展', '第三章 结局']);
  const t = await get(`/luis/content?item_id=${c.json.data[0].item_id}&source=路易斯书库&tab=小说`, cookie);
  assert.equal(t.json.content, '第一段。\n第二段。');
  const disc = await get('/luis/discovestyle?source=路易斯书库&tab=小说', cookie);
  const recent = disc.json.data.find((e) => e.title === '最近添加');
  const l = await get(recent.url.replace(base, '').replace('{{page}}', '1'), cookie);
  assert.equal(l.json.data[0].book_name, '测试长篇');
  assert.equal((await get(`/luis/content?item_id=${c.json.data[0].item_id}&source=路易斯书库&tab=小说`)).json.code, -3);
  assert.equal(lib.list().length, 1);
  assert.equal(u.username, 'member');
});

test('admin: luis-add-book / luis-list-books / luis-remove-book on a file DB', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qread-luis-admin-'));
  const cfg = { ...app.cfg, dbPath: path.join(dir, 'a.db'), dataDir: dir };
  const txt = path.join(dir, 'b.txt');
  fs.writeFileSync(txt, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('第1章 甲\n正文甲\n第2章 乙\n正文乙\n', 'utf8')]));
  const lines = [];
  admin(['luis-add-book', txt, '--name', '文件书', '--author', '丁'], { cfg, out: (s) => lines.push(s) });
  assert.match(lines[0], /book 1: 文件书, 2 chapters/);
  admin(['luis-list-books'], { cfg, out: (s) => lines.push(s) });
  assert.match(lines[1], /1\t文件书\t丁\t2 chapters/);
  admin(['luis-remove-book', '1'], { cfg, out: (s) => lines.push(s) });
  assert.equal(lines[2], 'removed');
  admin(['luis-cache-clear'], { cfg, out: (s) => lines.push(s) });
  assert.match(lines[3], /cleared/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('splitChapters and decodeText', () => {
  const ch = splitChapters('序章\n开篇\n第一章 风起\n一\n二\n第二卷 云涌\n第二章 云涌\n三');
  assert.deepEqual(ch.map((c) => [c.title, !!c.isVolume]), [['序章', false], ['第一章 风起', false], ['第二卷 云涌', true], ['第二章 云涌', false]]);
  assert.equal(ch[1].content, '一\n二');
  const flat = splitChapters('a'.repeat(5000) + '\n' + 'b'.repeat(5000));
  assert.equal(flat.length, 2);
  assert.equal(flat[0].title, '第1部分');
  assert.equal(splitChapters('').length, 0);
  assert.equal(decodeText(Buffer.from([0xb2, 0xe2, 0xca, 0xd4])), '测试');
  assert.equal(decodeText(Buffer.from('测试', 'utf8')), '测试');
});

test('维基文库 adapter: search dedupes chapters into works, header author, chapter order, simplified text', async () => {
  const ws = wikisourceAdapter({ fetchImpl: fakeWiki });
  const s = await ws.search('红楼梦', 1);
  assert.deepEqual(s.map((b) => b.name), ['紅樓夢', '後紅樓夢']);
  assert.equal(s[0].intro, '紅樓夢 第一回');
  const d = await ws.detail('紅樓夢');
  assert.equal(d.author, '曹雪芹（前八十回）；高鶚（後四十回）');
  assert.match(d.intro, /^清代長篇小說，參見紅樓夢 \(消歧義\)。/);
  assert.equal(d.latestChapter, '第三回');
  const c = await ws.catalog('紅樓夢');
  assert.deepEqual(c.map((x) => x.id), ['紅樓夢/第一回', '紅樓夢/第二回', '紅樓夢/第三回']);
  assert.equal(c[0].title, '第一回 甄士隱夢幻識通靈');
  // a {{versions}} page: editions become volumes
  const v = await ws.detail('水滸傳');
  assert.equal(v.author, '施耐庵、羅貫中');
  assert.equal(v.latestChapter, '2 个版本');
  // volume subpages are expanded, other subpages stay
  const lz = await ws.catalog('聊齋志異');
  assert.deepEqual(lz.map((x) => [x.title, !!x.isVolume]), [['作者自志', false], ['第一卷', true], ['考城隍', false], ['耳中人', false], ['第二卷', true], ['金世成', false], ['董生', false]]);
  assert.equal(lz[5].id, '聊齋志異/第02卷#sec=1');
  const story = await ws.content('聊齋志異/第02卷#sec=2');
  assert.equal(story.content, '故事2正文。');
  const vc = await ws.catalog('水滸傳');
  assert.deepEqual(vc.map((x) => [x.id, !!x.isVolume]), [['水滸傳 (100回本)', true], ['水滸傳 (100回本)/第001回', false], ['水滸傳 (100回本)/第002回', false], ['水滸傳 (70回本)', true], ['水滸傳 (70回本)/第001回', false], ['水滸傳 (70回本)/第002回', false]]);
  const t = await ws.content('紅樓夢/第一回');
  assert.equal(t.title, '第一回');
  assert.equal(t.content, '第一段文字。\n第二段文字。');
  const lists = await ws.discoverList('cat:章回小說', 1);
  assert.deepEqual(lists.map((b) => b.name), ['紅樓夢', '水滸傳']);
  assert.deepEqual((await ws.discoverList('list:紅樓夢|西遊記', 1)).map((b) => b.id), ['紅樓夢', '西遊記']);
  assert.equal(chapterLinks('X', '[[X/a|A]] [[Y/b]] [[X/a]]').length, 1);
  assert.equal(stripHtml('<p>a<br>b</p><table><tr><td>t</td></tr></table>'), 'a\nb');
  // a real chapter page: navigation paragraph, title, footnote markers, nested licence box at the end
  const page = '<div class="mw-parser-output"><style>.x{}</style><p><a href="/x">回目录</a> <a href="/y">下一回</a></p><hr><div class="center"><b>第一回 甄士隱夢幻識通靈</b></div>' +
    '<p>正文一<sup class="reference"><a>[1]</a></sup></p><div class="poem"><p>詩一<br>詩二</p></div><p>正文二</p>' +
    '<div class="mw-references-wrap"><ol class="references"><li>注一</li></ol></div>' +
    '<div class="licenseContainer licenseBanner"><div><div><p>此清朝作品在全世界都属于公有领域</p></div></div></div><div class="licensetpl"><p><span>PD</span></p></div></div>';
  assert.equal(stripHtml(page), '第一回 甄士隱夢幻識通靈\n正文一\n詩一\n詩二\n正文二');
  assert.equal(stripHtml('<p>上一回 · 下一回</p><p>x</p><p>目录</p>'), 'x');
});
