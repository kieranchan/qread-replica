// The site adapters' parsers on fixtures shaped like the live pages (2026-10-29), the shared client (pacing, retry,
// GB18030) and the adapters wired through a fake fetch.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient, gbkEncode, decodeEntities, lines, text, HttpError } from '../src/luis/adapters/http.mjs';
import { parseSearch as qdSearch, parseBook as qdBook, parseCatalog as qdCatalog, parseChapter as qdChapter, qidianAdapter } from '../src/luis/adapters/qidian.mjs';
import { bookOf, parseReader, qimaoAdapter } from '../src/luis/adapters/qimao.mjs';
import { parseSearch as jjSearch, parseBook as jjBook, parseCatalog as jjCatalog, parseChapter as jjChapter, jjwxcAdapter } from '../src/luis/adapters/jjwxc.mjs';

const resp = (body, { status = 200, type = 'text/html; charset=utf-8' } = {}) => new Response(typeof body === 'string' ? body : body, { status, headers: { 'Content-Type': type } });

test('client: minimum interval between requests, retry on 5xx, HttpError on 4xx', async () => {
  let t = 0;
  const starts = [];
  let calls = 0;
  const client = createClient({
    minIntervalMs: 100,
    now: () => t,
    sleep: async (ms) => { t += ms; },
    fetchImpl: async (url) => {
      starts.push(t);
      calls++;
      if (url.endsWith('/flaky') && calls === 1) return resp('oops', { status: 503 });
      if (url.endsWith('/missing')) return resp('no', { status: 404 });
      return resp('<p>ok</p>');
    },
  });
  await client.get('http://x/a');
  await client.get('http://x/b');
  assert.deepEqual(starts, [0, 100]);
  const r = await client.get('http://x/flaky');
  assert.equal(r.text, '<p>ok</p>');
  await assert.rejects(client.get('http://x/missing'), (e) => e instanceof HttpError && e.status === 404);
});

test('gb18030 decoding and encoding, entities, lines', async () => {
  const gbk = Buffer.from([0xb6, 0xb7, 0xc6, 0xc6]);
  const client = createClient({ minIntervalMs: 0, fetchImpl: async () => resp(gbk, { type: 'text/html' }) });
  assert.equal((await client.get('http://x/', { charset: 'gb18030' })).text, '斗破');
  assert.equal(gbkEncode('斗破'), '%B6%B7%C6%C6');
  assert.equal(decodeEntities('a&nbsp;b&#20013;&#x6587;&amp;'), 'a b中文&');
  assert.deepEqual(lines('<p>一</p><div>二<br>三</div>  <p> </p>'), ['一', '二', '三']);
  assert.equal(text('<b>x</b> &lt;y&gt;'), 'x <y>');
});

// ---------------- 起点 ----------------
const QD_SEARCH = `<div class="y-list"><a class="_bookWrapper_e9qzy_9 _listItem_lrbl7_246" href="//m.qidian.com/chapter/1209977/0/" title="斗破苍穹在线阅读" data-bid="1209977"><div><img src="x.png" data-src="//bookcover.yuewen.com/qdbimg/349573/1209977/180" class="_bookImg_e9qzy_15"></div><div><h2 class="_searchBookName_lrbl7_250"><mark>斗破苍穹</mark></h2><p class="_searchBookDesc_lrbl7_337">这里是属于斗气的世界</p><div class="_bookTips_e9qzy_161"><p class="_searchBookAuthor_lrbl7_429">天蚕土豆</p><div class="_tags_lrbl7_516"><p>玄幻</p><p>完结</p><p>533.23万字</p></div></div></div></a>
<a class="_bookWrapper_e9qzy_9" href="//m.qidian.com/chapter/2211027/0/" title="x" data-bid="2211027"><h2 class="_searchBookName_lrbl7_250">斗破之无上之境</h2><p class="_searchBookAuthor_lrbl7_429">夜雨</p><div class="_tags_lrbl7_516"><p>诸天无限</p><p>连载</p><p>1001.37万字</p></div></a></div>`;
const QD_BOOK = `<html><head><title>斗破苍穹(天蚕土豆) 小说在线阅读</title><meta name="description" content="天蚕土豆创作的玄幻小说《斗破苍穹》,已更新1681章,最新章节:《斗破苍穹：斗帝之路》手游·角色传记（下）。这里是">
<meta property="og:novel:status" content="完本"><meta property="og:novel:category" content="异世大陆"><meta property="og:image" content="//bookcover.yuewen.com/qdbimg/349573/1209977/180">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Book","name":"斗破苍穹","image":"https://bookcover.yuewen.com/qdbimg/349573/1209977/600","author":{"@type":"Person","name":"天蚕土豆"},"genre":"异世大陆","description":"这里是属于斗气的世界","additionalProperty":[{"@type":"PropertyValue","name":"连载状态","value":"完本"},{"@type":"PropertyValue","name":"最新章节","value":"《斗破苍穹：斗帝之路》手游·角色传记（下）"}]}]}</script></head>
<body><span>533.22</span><span>万字</span><time itemprop="dateModified" datetime="2018-09-19 09:59:53">2018-09-19</time></body></html>`;
const QD_CATALOG = `<div class="_statusWrapper_1x6xn_142"><h4>已经完本 · 共3章</h4></div><a class="_secondHeader_1x6xn_262" href="//m.qidian.com/chapter/1209977/427202307/" data-cid="427202307"><h3>《斗破苍穹：斗帝之路》手游·角色传记（下）</h3><p>2018-09-19 09:59:53</p></a>
<div class="y-list"><div class="y-list__content"><div class="y-list__item"><div class="_chapterBar_1x6xn_498">作品相关</div><div class="_chapterItemWrapper_1x6xn_1"><a href="//m.qidian.com/chapter/1209977/23724973/">上架感言<span class="_tag_1">免费</span></a></div></div>
<div class="y-list__item"><div class="_chapterBar_1x6xn_498">第一卷 天才的陨落</div><a href="//m.qidian.com/chapter/1209977/427202284/">第一章 陨落的天才</a><a href="//m.qidian.com/chapter/1209977/427202307/"><span>《斗破苍穹：斗帝之路》手游·角色传记（下）</span><i class="qd-icon lock"></i></a></div></div></div>`;
const QD_CHAPTER = `<main><h1 class="title text-1.3em">第一章 陨落的天才</h1><div class="content mt-1.5em r-font-black"><p>“斗之气，三段！”</p><p>望着测验魔石碑。</p></div></main><div class="comment-wrap"><p>本章说</p><p>好书等你评</p></div>`;

test('起点: search items, book metadata, catalog with volumes and the header link skipped, chapter text without the comments', async () => {
  const s = qdSearch(QD_SEARCH);
  assert.equal(s.length, 2);
  assert.deepEqual([s[0].id, s[0].name, s[0].author, s[0].category, s[0].status, s[0].wordCount, s[0].cover], ['1209977', '斗破苍穹', '天蚕土豆', '玄幻', '完结', '533.23万字', 'https://bookcover.yuewen.com/qdbimg/349573/1209977/180']);
  assert.equal(s[0].intro, '这里是属于斗气的世界');
  const b = qdBook(QD_BOOK, '1209977');
  assert.deepEqual([b.name, b.author, b.category, b.status, b.latestChapter, b.wordCount, b.cover, b.updatedAt], ['斗破苍穹', '天蚕土豆', '异世大陆', '完本', '《斗破苍穹：斗帝之路》手游·角色传记（下）', '533.22万字', 'https://bookcover.yuewen.com/qdbimg/349573/1209977/600', '2018-09-19 09:59:53']);
  const c = qdCatalog(QD_CATALOG, '1209977');
  assert.deepEqual(c.map((x) => [x.title, !!x.isVolume, !!x.isVip]), [['作品相关', true, false], ['上架感言', false, false], ['第一卷 天才的陨落', true, false], ['第一章 陨落的天才', false, false], ['《斗破苍穹：斗帝之路》手游·角色传记（下）', false, true]]);
  assert.equal(c[1].id, '1209977/23724973');
  const ch = qdChapter(QD_CHAPTER);
  assert.equal(ch.title, '第一章 陨落的天才');
  assert.equal(ch.content, '“斗之气，三段！”\n望着测验魔石碑。');
  // wired adapter: search -> detail -> catalog -> content, the mobile UA, a challenge page fails
  const urls = [];
  const a = qidianAdapter({ minIntervalMs: 0, fetchImpl: async (url, init) => {
    urls.push(url);
    assert.match(init.headers['User-Agent'], /iPhone/);
    if (url.includes('/soushu/')) return resp(QD_SEARCH);
    if (url.endsWith('/catalog/')) return resp(QD_CATALOG);
    if (url.includes('/book/')) return resp(QD_BOOK);
    if (url.includes('/chapter/1209977/23724973/')) return resp(QD_CHAPTER);
    return resp('<html><head><script>var name = "x-waf-captcha-referer";</script></head><body></body></html>', { status: 202 });
  } });
  assert.equal((await a.search('斗破苍穹', 1))[0].id, '1209977');
  assert.equal((await a.detail('1209977')).author, '天蚕土豆');
  assert.equal((await a.catalog('1209977')).length, 5);
  assert.equal((await a.content('1209977/23724973')).content.split('\n').length, 2);
  await assert.rejects(a.content('1209977/999'), /验证页/);
  assert.deepEqual(await a.search('x', 2), []);
  assert.ok(urls[0].startsWith('https://m.qidian.com/soushu/'));
});

// ---------------- 七猫 ----------------
test('七猫: api books, paginated chapter list, reader page text', async () => {
  const b = bookOf({ book_id: '1691211', title: '重生夺你山河', author: '重生踏雪', intro: '简介', image_link: 'c.jpg', category2_name: '古代言情', is_over_txt: '完结', words_num: '20.4万字', latest_chapter_title: '第100章 终', read_url: 'https://www.qimao.com/shuku/1691211/' });
  assert.deepEqual([b.id, b.name, b.status, b.wordCount, b.category, b.latestChapter], ['1691211', '重生夺你山河', '完结', '20.4万字', '古代言情', '第100章 终']);
  assert.equal(bookOf({ book_id: '1', title: 'x', words_num: '20.4' }).wordCount, '20.4万字');
  const r = parseReader('<h2 class="chapter-title" data-v-1>第1章  以血为祭</h2><div class="article" data-v-1><p>潮湿阴暗的大牢中。</p><p>“是！”</p></div><div class="other"><p>推荐</p></div>');
  assert.equal(r.title, '第1章 以血为祭');
  assert.equal(r.content, '潮湿阴暗的大牢中。\n“是！”');
  const chapters = (page) => Array.from({ length: page === 1 ? 100 : 3 }, (_, i) => ({ id: `c${(page - 1) * 100 + i + 1}`, title: `第${(page - 1) * 100 + i + 1}章`, is_vip: '0', update_time: '1707205940', words: '2000' }));
  const a = qimaoAdapter({ minIntervalMs: 0, fetchImpl: async (url) => {
    const u = new URL(url);
    if (u.pathname.endsWith('/search/result')) return resp(JSON.stringify({ data: { page_data: { count: '1' }, search_list: [{ book_id: '1691211', title: '重生夺你山河', author: '重生踏雪' }], all_search_list: [] } }), { type: 'application/json' });
    if (u.pathname.endsWith('/book-detail/main-info')) return resp(JSON.stringify(u.searchParams.get('book_id') ? { data: { book_detail: { title: '重生夺你山河', author: '重生踏雪', words_num: '20.4', latest_chapter_title: '第103章' } } } : { errors: { title: '请求参数错误' } }), { type: 'application/json' });
    if (u.pathname.endsWith('/book/chapter-list')) return resp(JSON.stringify({ data: { chapters: chapters(Number(u.searchParams.get('page'))) } }), { type: 'application/json' });
    if (u.pathname === '/shuku/1691211-c1/') return resp('<h2 class="chapter-title">第1章</h2><div class="article"><p>正文</p></div>');
    return resp('nope', { status: 404 });
  } });
  assert.equal((await a.search('重生', 1))[0].name, '重生夺你山河');
  assert.equal((await a.detail('1691211')).latestChapter, '第103章');
  const c = await a.catalog('1691211');
  assert.equal(c.length, 103);
  assert.equal(c[102].id, '1691211/c103');
  assert.equal((await a.content('1691211/c1')).content, '正文');
});

// ---------------- 晋江 ----------------
const JJ_SEARCH = `<h3 class="title"><a href="//www.jjwxc.net/onebook.php?novelid=8043464" target="_blank">斗破苍穹</a><span>(2023-05-23)</span></h3><div class="info">7万亿年前，天地混沌初开</div><div>作者：<a href="x">奕小婷</a></div>
<h3 class="title"><a href="//www.jjwxc.net/onebook.php?novelid=10651373">斗破苍穹</a>(2026-03-28)</h3><div>小说以斗气大陆为背景</div>作者： <a>天蚕土豆呀</a>`;
const JJ_BOOK = `<html><head><title>《斗破苍穹》奕小婷_晋江文学城_【原创小说|言情小说】</title><meta name="Keywords" content="《斗破苍穹》,奕小婷,正剧|最新更新:2023-05-26 18:33:32|作品积分：54279"></head><body>
<a href="//www.jjwxc.net/oneauthor.php?authorid=5626335"><span itemprop="name">奕小婷</span></a>
<ul class="rightul"><li>文章类型：<span itemprop="genre">原创-言情-近代现代-爱情</span></li><li>文章进度：<span itemprop="updataStatus">连载</span></li><li>全文字数：<span itemprop="wordCount">4506字</span></li></ul>
<div class="smallreadbody"><img class="noveldefaultimage" itemprop="image" src="https://i9-static.jjwxc.net/novelimage.php?novelid=8043464"><div id="novelintro" itemprop="description">7万亿年前，天地混沌初开<br>第二段</div></div>
<div class="smallreadbody">内容标签：<a href="t1">正剧</a> <a href="t2">重生</a></div>
<table id="oneboolt"><tr><td colspan="6" class="sptd">tools</td></tr>
<tr itemprop="chapter"><td align="center">1</td><td><span itemprop="headline"><div><a itemprop="url" href="http://www.jjwxc.net/onebook.php?novelid=8043464&chapterid=1">顺势而生</a></div></span></td><td>女主的出现</td><td itemprop="wordCount">299</td><td class="chapterclick"></td><td title="章节存稿时间：2023-05-23 17:07:13"><span>2023-05-23 20:22:15</span></td></tr>
<tr itemprop="chapter"><td align="center">2</td><td><span itemprop="headline"><div><a href="//my.jjwxc.net/onebook_vip.php?novelid=8043464&chapterid=2">VIP 第二章</a></div></span></td><td></td><td>3000</td><td></td><td>2023-05-24</td></tr></table></body></html>`;
const JJ_CHAPTER = `<html><head><title>《斗破苍穹》奕小婷　^第1章^ 最新更新:2023 晋江文学城</title></head><body><td><div class="noveltext " onselectstart="return false"><div style="width: 100%; text-align: center;"><span class="favorite_novel">[添加书签]</span>[<span id="invite">推荐给朋友</span>]<script>displayyrt("#yrt3", '');</script><span>[投诉]</span><div id="report_box"><div><a>投诉色情有害</a></div><div><a>其他</a></div></div><div id="float_favorite"><div class="float_title"><span>文章收藏</span></div><div class="float_comment"><div><font>为收藏文章分类</font></div></div><div class="float_foot"><a>定制收藏类别</a>&nbsp;<a>查看收藏列表</a></div></div></div><div align="center"><h2>顺势而生</h2><br/></div><div style="clear:both;"></div><div id="paragraph_comment_content"><br>　　1992年秋，天秤座的尾巴。<br>　　“哎哟，我的祖宗列”</div><div id="favoriteshow_3" style="display:none"></div><div align="right"><span class="favorite_novel">插入书签</span></div><div id="note_danmu_wrapper"><div class="note_main"><br>作者的话</div><div class="recommend_novel_box"></div></div></div></td></body></html>`;

test('晋江: search rows, book metadata, chapter rows with vip, chapter text without the toolbars', async () => {
  const s = jjSearch(JJ_SEARCH);
  assert.equal(s.length, 2);
  assert.deepEqual([s[0].id, s[0].name, s[0].author, s[0].intro, s[0].updatedAt], ['8043464', '斗破苍穹', '奕小婷', '7万亿年前，天地混沌初开', '2023-05-23']);
  assert.equal(s[1].author, '天蚕土豆呀');
  const b = jjBook(JJ_BOOK, '8043464');
  assert.deepEqual([b.name, b.author, b.category, b.status, b.wordCount, b.cover, b.updatedAt], ['斗破苍穹', '奕小婷', '原创-言情-近代现代-爱情', '连载', '4506字', 'https://i9-static.jjwxc.net/novelimage.php?novelid=8043464', '2023-05-26 18:33:32']);
  assert.equal(b.intro, '7万亿年前，天地混沌初开\n第二段');
  assert.deepEqual(b.tags, ['正剧', '重生']);
  const c = jjCatalog(JJ_BOOK, '8043464');
  assert.deepEqual(c.map((x) => [x.id, x.title, x.isVip, x.wordCount]), [['8043464/1', '顺势而生 女主的出现', false, '299'], ['8043464/2', 'VIP 第二章', true, '3000']]);
  assert.equal(c[0].time, '2023-05-23 17:07:13');
  const ch = jjChapter(JJ_CHAPTER);
  assert.equal(ch.title, '顺势而生');
  assert.equal(ch.content, '1992年秋，天秤座的尾巴。\n“哎哟，我的祖宗列”\n\n【作者有话说】\n作者的话');
  const a = jjwxcAdapter({ minIntervalMs: 0, fetchImpl: async (url) => {
    if (url.includes('search.php')) {
      assert.match(url, /kw=%B6%B7%C6%C6%B2%D4%F1%B7&t=1/);
      return resp(Buffer.from(JJ_SEARCH, 'utf8'), { type: 'text/html' });
    }
    if (url.includes('chapterid=1')) return resp(Buffer.from(JJ_CHAPTER, 'utf8'), { type: 'text/html' });
    return resp(Buffer.from(JJ_BOOK, 'utf8'), { type: 'text/html' });
  } });
  // (the fixtures are utf-8 here; the live pages are GB18030 and decoded with charset gb18030 — covered by the client test)
  const s2 = await a.search('斗破苍穹', 1);
  assert.ok(s2.length >= 1);
});
