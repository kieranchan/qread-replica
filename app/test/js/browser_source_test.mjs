// Node checks of the pure helpers of the 「浏览器」 时光源 page (lib/util/source/browser_source_page.dart): the name cleaning, the
// chapter-link filters, the directory clustering and the content line filter. The DOM functions (getinfo / chapter / content) run in
// the app's web view; see app/README.md for the phone check.
//
//   node --test test/js/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dart = fs.readFileSync(path.join(here, '..', '..', 'lib', 'util', 'source', 'browser_source_page.dart'), 'utf8');

/** The html inside the Dart raw string. */
export function pageHtml() {
  const start = dart.indexOf("r'''") + 4;
  const end = dart.indexOf("'''", start);
  return dart.slice(start, end);
}

/** The page's script, evaluated with a window that never becomes ready (no bridge calls are made). */
function loadScript() {
  const html = pageHtml();
  const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
  const sandbox = { window: { addEventListener() {} }, URL, JSON, console };
  vm.createContext(sandbox);
  vm.runInContext(script, sandbox);
  return sandbox;
}

const page = loadScript();

test('the page declares every entry point the app calls', () => {
  const html = pageHtml();
  for (const fn of ['search', 'info', 'getinfo', 'chapter', 'content']) assert.ok(html.includes(`async function ${fn}(`), fn);
  assert.ok(html.includes("'CookieJar'"));
  assert.match(html, /var isCookieJar\s*=\s*false/);
  assert.ok(!html.includes('qread.xyz'));
  assert.ok(!html.includes('<script src='), 'no external scripts');
});

test('cleanTitle: the book name out of a page title', () => {
  const t = page.cleanTitle;
  assert.equal(t('重建聊斋最新章节_无弹窗全文免费阅读_笔趣阁'), '重建聊斋');
  assert.equal(t('重建聊斋,重建聊斋全文免费在线阅读_笔趣阁'), '重建聊斋');
  assert.equal(t('《斗破苍穹》最新章节列表 - 某某小说网'), '斗破苍穹');
  assert.equal(t('斗破苍穹 - 天蚕土豆 - 某站'), '斗破苍穹');
  assert.equal(t('  诡秘之主小说在线阅读_起点'), '诡秘之主');
  assert.equal(t('第一序列'), '第一序列');
});

test('cleanAuthor / cleanIntro', () => {
  assert.equal(page.cleanAuthor('作者：野亮'), '野亮');
  assert.equal(page.cleanAuthor('野亮 著'), '野亮');
  assert.equal(page.cleanAuthor('天蚕土豆/某某'), '天蚕土豆');
  const intro = page.cleanIntro('第一句。第二句！&nbsp;&nbsp;第三句？ 第四句');
  assert.equal(intro, '第一句。\n第二句！\n第三句？\n第四句');
  assert.equal(page.cleanIntro('x'.repeat(1200)).length, 1003);
});

test('field: what follows a label', () => {
  const text = '重建聊斋 作者：野亮 状态：全本 分类: 仙侠 最新章节：第一百七十五章 王淳元';
  assert.equal(page.field(text, '作\\s*[者家]', 20), '野亮');
  assert.equal(page.field(text, '状\\s*态', 8), '全本');
  assert.equal(page.field(text, '(?:分\\s*类|类\\s*[型别])', 12), '仙侠');
  assert.equal(page.field('没有', '作\\s*者', 20), '');
  assert.equal(page.field('垃圾分类人人有责，分类：仙侠', '(?:分\\s*类|类\\s*[型别])', 12), '仙侠');
  assert.equal(page.field('创作者很多', '作\\s*[者家]', 20), '');
  assert.equal(page.field('野亮 字数：44万字 状态：全本', '字\\s*数', 12), '44万字');
  assert.equal(page.pickWords('小说 野亮 44万字 全本 相关小说 最强泷影 344万字'), '44万字');
  assert.equal(page.pickWords('字数：12.5万字'), '12.5万字');
  assert.equal(page.pickWords('字数：未知'), '');
  assert.equal(page.pickWords('全本'), '');
});

test('isChapterHref: navigation and site pages are not chapters', () => {
  const toc = 'https://www.biquge.tw/book/70114/';
  const ok = (u) => page.isChapterHref(u, toc);
  assert.ok(ok('https://www.biquge.tw/book/70114/23593795.html'));
  assert.ok(ok('https://site.test/read/70114_1.html'));
  assert.ok(ok('https://site.test/1234.html'));
  assert.ok(!ok('https://www.biquge.tw/'));
  assert.ok(!ok(toc));
  assert.ok(!ok(toc + '#top'));
  assert.ok(!ok('https://www.biquge.tw/sort/xuanhuan/'));
  assert.ok(!ok('https://www.biquge.tw/top/'));
  assert.ok(!ok('https://www.biquge.tw/history.html'));
  assert.ok(!ok('https://site.test/login.php'));
  assert.ok(!ok('https://site.test/down/1.txt'));
  assert.ok(!ok('https://site.test/book/1/cover.jpg'));
  assert.ok(!ok('javascript:void(0)'));
  assert.ok(!ok('mailto:a@b.c'));
});

test('isChapterText: chapter names pass, buttons do not', () => {
  const ok = (t) => page.isChapterText(t);
  assert.ok(ok('第一百七十五章 王淳元'));
  assert.ok(ok('第1章 重生'));
  assert.ok(ok('楔子'));
  assert.ok(ok('番外：十年后'));
  for (const t of ['首页', '书架', '我的书架', '排行', '书库', '繁体', '目录', '返回目录', '返回书页', '下一页', '上一页', '尾页', '第2页', '倒序', '正序',
    '查看全部章节列表', '开始阅读', '手机版', 'TXT下载', '下载APP', '加入书架', '>>', '', '   ', 'x'.repeat(81), '好色小姨 收藏']) {
    assert.ok(!ok(t), JSON.stringify(t));
  }
});

test('mainPrefix: the chapters directory wins over the site-wide one the recommendations share', () => {
  const urls = [];
  for (let i = 0; i < 20; i++) urls.push(`https://www.biquge.tw/book/70114/2359${1000 + i}.html`);
  for (let i = 0; i < 4; i++) urls.push(`https://www.biquge.tw/book/${500 + i}.html`);
  assert.equal(page.mainPrefix(urls), 'https://www.biquge.tw/book/70114/');
  assert.equal(page.mainPrefix(['https://a.test/1.html', 'https://a.test/2.html']), '');
  assert.equal(page.mainPrefix(['https://a.test/r/1.html', 'https://a.test/r/2.html', 'https://a.test/r/3.html', 'https://a.test/x/4.html']), 'https://a.test/r/');
  assert.equal(page.mainPrefix([]), '');
});

test('filterContentLines: navigation and advert lines go, prose stays', () => {
  const text = [
    '上一章 目录 下一章',
    '一秒记住【笔趣阁】，精彩小说无弹窗免费阅读！',
    '　　“我先返回。”他说。',
    '　　聊斋的夜晚很安静，会员们都睡了。',
    'https://www.biquge.tw',
    '字体：',
    '大',
    '返回目录',
    '',
    '　　第二段正文。',
    '手机用户请浏览m.biquge.tw阅读，更优质的阅读体验。',
    '本章完',
  ].join('\n');
  assert.equal(page.filterContentLines(text), ['“我先返回。”他说。', '聊斋的夜晚很安静，会员们都睡了。', '第二段正文。'].join('\n'));
});

test('absUrl / squeeze', () => {
  assert.equal(page.absUrl('23593795.html', 'https://www.biquge.tw/book/70114/'), 'https://www.biquge.tw/book/70114/23593795.html');
  assert.equal(page.absUrl('/book/1.html', 'https://www.biquge.tw/book/70114/@chrome'), 'https://www.biquge.tw/book/1.html');
  assert.equal(page.absUrl('::bad', 'not a url'), '');
  assert.equal(page.squeeze('  a 　\n b  '), 'a b');
});
