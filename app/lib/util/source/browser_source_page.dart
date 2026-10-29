// util/source/browser_source_page.dart — the page of the built-in 「浏览器」 时光源 (see browser_source.dart).
//
// The original fetches this page from `http://yuan.qread.xyz/get-html?url=…` (an `@aes` page served by qread.xyz, 0x1b9adc); the
// replica never calls that service, so this is its own generic parser of a web-novel site, written against the same page API
// (`getinfo(html, bookurl)` 0xfcf350, `info` / `chapter` / `content` / `search` as every 时光源). Plain DOM, no jQuery, no network of
// its own: pages come through the app's `webview` handler and text through `htmlToText`.
//
// What it does: `getinfo` reads name / author / kind / status / latest chapter / intro / cover from the open page (meta tags first,
// then the text), `chapter` collects the links of the page (and its 下一页 pages), drops navigation links and keeps the links that share
// the most common directory, `content` takes the biggest text block of a chapter page, follows its 下一页 pages and drops the usual
// navigation / advert lines.
//
// Kept as a Dart raw string so that `Sourcedata.byUrl` can hand the source out synchronously; test/js/browser_source_test.mjs reads
// the script out of this file and runs its pure helpers under Node.
const String browserSourcePage = r'''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>浏览器</title>
</head>
<body></body>
<script>
var isCookieJar = false;

async function callHandler(name) {
  var args = Array.prototype.slice.call(arguments, 1);
  return await window.flutter_inappwebview.callHandler.apply(window.flutter_inappwebview, [name].concat(args));
}

const flutterBridge = {
  async webview(url, js, html, body, header) {
    try { return (await callHandler('webview', url, js, html, body, header, '', '')) || ''; } catch (e) { return ''; }
  },
  async htmlToText(str) {
    try { return (await callHandler('htmlToText', str)) || ''; } catch (e) { return ''; }
  },
  async text(type, str) {
    try { return await callHandler('text', type, str); } catch (e) { return false; }
  },
  async log(str) {
    try { return await callHandler('log', String(str)); } catch (e) { return false; }
  }
};

const cache = {
  async get(key) { try { return await callHandler('cache.get', key); } catch (e) { return null; } },
  async set(key, value) { try { return await callHandler('cache.set', key, value); } catch (e) { return null; } }
};

(function () {
  function ready() { callHandler('CookieJar', isCookieJar).catch(function () {}); }
  if (window.flutter_inappwebview) ready(); else window.addEventListener('flutterInAppWebViewPlatformReady', ready);
})();

// ---------------------------------------------------------------------------------------------------------------------------------
// helpers (no DOM: test/js/browser_source_test.mjs runs them under Node)

// html the app already holds (阅读模式 hands the open page over through getinfo); used once by the first chapter page
var pages = {};
var TOC_KEY = 'browser-toc:';

function squeeze(s) { return (s || '').replace(/[\s　]+/g, ' ').trim(); }
function clip(s, n) { s = s || ''; return s.length > n ? s.substring(0, n) + '...' : s; }
function absUrl(href, base) { try { return new URL(href || '', base).href; } catch (e) { return ''; } }
function pathOf(url) { try { return new URL(url).pathname; } catch (e) { return ''; } }
function segments(url) { return pathOf(url).split('/').filter(function (s) { return s.length > 0; }); }
function headers(referer) { return JSON.stringify({ Referer: referer }); }

// 「书名_最新章节_站名」 / 「书名 - 作者 - 站名」 / 「《书名》最新章节列表」 -> 书名
var NAME_NOISE = /(最新章节列表|最新章节|章节列表|章节目录|全文免费阅读|免费阅读|在线阅读|全文阅读|无弹窗|无弹框|txt下载|下载|小说网|笔趣阁|目录|简介|正版|全本|小说)+$/i;
function cleanTitle(title) {
  var t = squeeze(title).replace(/^[\s「『【〖（(\[《]+/, '');
  var first = t.split(/\s*[_|｜丨\-—–,，]\s*/)[0] || t;
  if (first.indexOf('》') >= 0) first = first.split('》')[0];
  first = first.replace(/[》」』】〗）)\]]+$/, '').trim();
  var cleaned = first.replace(NAME_NOISE, '').trim();
  return cleaned || first;
}

// what a page writes after 作者 / 分类 / 状态 (stops at the next separator); the label must start a word (not 「垃圾分类」)
var FIELD = '[^\\s<>,，、/／|｜丨:：()（）\\[\\]【】《》]';
function field(text, label, max) {
  var m = (text || '').match(new RegExp('(?:^|[^\\u4e00-\\u9fa5a-zA-Z])' + label + '\\s*[:：]?\\s*(' + FIELD + '{1,' + max + '})'));
  return m ? m[1] : '';
}
function cleanAuthor(a) {
  return squeeze(a).replace(/^作\s*[者家]\s*[:：]?\s*/, '').replace(/^著\s*[:：]?\s*/, '').split(/[/／|｜丨,，、]/)[0].replace(/\s*著$/, '').trim();
}
// the book's word count: a labelled 字数, else the first 「n万字」 of the page (the book's own line comes before the recommendations)
function pickWords(text) {
  var w = field(text, '字\\s*数', 12);
  if (w && !/\d/.test(w)) w = '';
  if (!w) {
    var m = (text || '').match(/(\d+(?:\.\d+)?)\s*万\s*字/);
    if (m) w = m[1] + '万字';
  }
  return w;
}
function cleanIntro(s) {
  var t = (s || '').replace(/(?:&nbsp;| )+/g, ' ').replace(/[ \t　]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim();
  t = t.replace(/\s*([。！？!?…]+[”」』\]\}\)）】〗〕〉]?)\s*/g, '$1\n').replace(/\n{2,}/g, '\n').trim();
  return clip(t, 1000);
}

var HREF_SKIP = /\/(login|logout|register|signup|passport|user|users|member|account|search|sort|sorts|rank|ranks|ranking|top|tag|tags|category|author|authors|xiazai|download|down|app|apps|buy|vip|pay|history|bookcase|bookshelf|shelf|fav|favorite|favorites|comment|comments|review|reviews|update|updates|help|about|contact|feedback|sitemap|modules|plus)(?=[\/._\-?]|$)/i;
function isChapterHref(href, pageUrl) {
  if (!/^https?:\/\//i.test(href)) return false;
  var p = pathOf(href);
  if (p === '' || p === '/' || href === pageUrl || href.split('#')[0] === pageUrl) return false;
  if (HREF_SKIP.test(p)) return false;
  if (/\.(jpe?g|png|gif|webp|svg|css|js|xml|json|zip|rar|7z|txt|epub|mobi|azw3?|apk|ipa|exe)$/i.test(p)) return false;
  return true;
}

var TEXT_SKIP = [
  /^(首页|主页|书架|我的书架|书库|排行|排行榜|分类|全部|更多|繁体|繁體|简体|登录|登錄|注册|註冊|搜索|目录|目錄|返回|书页|简介|详情|章节列表|全部章节|查看全部|查看全部章节|展开|收起|倒序|正序|升序|降序|上一页|下一页|上页|下页|尾页|末页|第一页|最后一页|上一章|下一章|上一节|下一节|加入书架|加入书签|收藏|收藏本书|投票|推荐|打赏|评论|举报|报错|章节报错|手机版|电脑版|手机阅读|客户端|下载|TXT下载|txt下载|APP|app|阅读记录|最新章节|最新更新)$/i,
  /^[上下首尾末前后]\s*[一\s]*[页頁]$/,
  /^第?[\s\d零〇一二三四五六七八九十百千]*[页頁]$/,
  /返回.*(简介|书页|目录|首页)/,
  /[倒正反逆顺順]序/,
  /(书架|书签|收藏|登录|注册|排行|首页|查看全部|章节列表|全部章节|展开|收起)/,
  /^(点击|软件|应用|安装|客户端|移动|手机|电脑|安卓|苹果|下载|阅读|app|pc|apk|ipa|exe|zip|rar|txt|epub)[\s.端版]*(点击|软件|应用|安装|客户端|移动|手机|电脑|安卓|苹果|下载|阅读|app|pc|apk|ipa|exe|zip|rar|txt|epub)*$/i,
  /开始阅读|立即阅读|免费阅读|继续阅读|全文阅读|在线阅读/,
  /[<>«»]/
];
function isChapterText(text) {
  var t = squeeze(text);
  if (!t || t.length > 80) return false;
  for (var i = 0; i < TEXT_SKIP.length; i++) if (TEXT_SKIP[i].test(t)) return false;
  return true;
}

// the directory most chapter links share: the most common prefix, or the longest one that still covers nearly all of them (so the
// chapters' own directory wins over the site-wide /book/ that the 「推荐」 links share too); '' when fewer than 3 links agree
function mainPrefix(urls) {
  var counts = {};
  urls.forEach(function (u) {
    var o;
    try { o = new URL(u); } catch (e) { return; }
    var segs = o.pathname.split('/').filter(function (s) { return s.length > 0; });
    for (var n = 1; n <= Math.min(4, segs.length - 1); n++) {
      var key = o.origin + '/' + segs.slice(0, n).join('/') + '/';
      counts[key] = (counts[key] || 0) + 1;
    }
  });
  var best = '', max = 0;
  Object.keys(counts).forEach(function (k) { if (counts[k] > max) { max = counts[k]; best = k; } });
  if (max < 3) return '';
  Object.keys(counts).forEach(function (k) { if (counts[k] >= max * 0.8 && k.length > best.length) best = k; });
  return best;
}

var STRONG_ADS = ['笔趣阁', '一秒记住', '天才一秒', '记住本站', '本站域名', '本站网址', '最新网址', '记住网址', '无弹窗', '请收藏', '收藏本站', '手机用户', '免费阅读', '全文阅读', '在线阅读', '小说网', '阅读网', '手机版', '电脑版', 'APP下载', '下载APP', 'app下载', 'Copyright', '版权所有', 'All Rights Reserved', '广告', '推广', '充值', 'VIP', '官方网站'];
var NAV_WORDS = ['首页', '返回', '关灯', '护眼', '字号', '字体', '报错', '上一章', '下一章', '上一页', '下一页', '上一节', '下一节', '目录', '书架', '书签', '本章完', '阅读记录', '分享', '举报', '推荐票', '月票', '打赏', '催更', '书评', '会员', '收藏', '加入', '章节列表', '内容简介', '作者信息', '作品信息'];
var LINE_EXACT = ['|', '大', '中', '小', '字体：', '字体:', '<', '>', '«', '»', '－', '—'];
function isAdLine(t) {
  if (LINE_EXACT.indexOf(t) >= 0) return true;
  if (/^(https?:\/\/|www\.)/i.test(t)) return true;
  if (t.length <= 200) for (var i = 0; i < STRONG_ADS.length; i++) if (t.indexOf(STRONG_ADS[i]) >= 0) return true;
  if (t.length <= 30 && !/[。！？!?…”]/.test(t)) for (var j = 0; j < NAV_WORDS.length; j++) if (t.indexOf(NAV_WORDS[j]) >= 0) return true;
  return false;
}
function filterContentLines(text) {
  var out = [];
  (text || '').split(/\r?\n/).forEach(function (line) {
    var t = line.replace(/^[\s　]+|[\s　]+$/g, '');
    if (t && !isAdLine(t)) out.push(t);
  });
  return out.join('\n');
}

// ---------------------------------------------------------------------------------------------------------------------------------
// DOM

function parse(html) { return new DOMParser().parseFromString(html || '', 'text/html'); }
function textOf(el) { return squeeze(el ? el.textContent : ''); }
function meta(doc, selectors) {
  for (var i = 0; i < selectors.length; i++) {
    var m = doc.querySelector(selectors[i]);
    var c = m ? (m.getAttribute('content') || '') : '';
    if (c.trim()) return c.trim();
  }
  return '';
}
function remove(doc, selector) {
  var els = doc.querySelectorAll(selector);
  for (var i = 0; i < els.length; i++) if (els[i].parentNode) els[i].parentNode.removeChild(els[i]);
}
function pickHeading(doc, name) {
  var hs = doc.querySelectorAll('h1, h2, h3');
  for (var i = 0; i < hs.length; i++) {
    var h = textOf(hs[i]).replace(/^[《「『【]|[》」』】]$/g, '').replace(NAME_NOISE, '').trim();
    if (!h || h.length > 40) continue;
    if (name.indexOf(h) === 0 || (h.indexOf(name) === 0 && h.length <= name.length + 2)) return h;
  }
  return name;
}
function pickLatest(doc, bodyText) {
  var m = meta(doc, ['meta[property*="chapter_name"]', 'meta[name*="chapter_name"]']);
  if (m) return m;
  var r = (bodyText || '').match(/最\s*新(?:\s*章\s*节)?\s*[:：]?\s*([^\n\r]{2,60}?)\s*(?:\n|$)/);
  return r ? squeeze(r[1]) : '';
}
function pickCover(doc, name, base) {
  var m = meta(doc, ['meta[property$="image"]', 'meta[name$="image"]']);
  if (!m) {
    var imgs = doc.querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) {
      var im = imgs[i];
      var src = im.getAttribute('src') || im.getAttribute('data-src') || im.getAttribute('data-original') || '';
      var hint = ((im.className || '') + ' ' + (im.id || '') + ' ' + (im.parentNode && im.parentNode.className || '') + ' ' + src).toLowerCase();
      if (src && (/cover|book|novel|pic|image/.test(hint) || (name && im.getAttribute('alt') === name))) { m = src; break; }
    }
  }
  return m ? absUrl(m, base) : '';
}
function nextLink(doc, base, current, textTest) {
  var as = doc.querySelectorAll('a[href]');
  for (var i = 0; i < as.length; i++) {
    var a = as[i], href = a.getAttribute('href') || '', t = squeeze(a.textContent);
    if (/^(javascript:|#|mailto:|tel:)/i.test(href)) continue;
    if (!textTest(t, a)) continue;
    var u = absUrl(href, base);
    if (/^https?:\/\//i.test(u) && u !== current) return u;
  }
  return '';
}
function nextTocPage(doc, url) {
  return nextLink(doc, url, url, function (t, a) {
    var rel = (a.getAttribute('rel') || '').toLowerCase();
    var ids = ((a.id || '') + ' ' + (a.className || '')).toLowerCase();
    return /^下一?[页頁]$/.test(t) || rel === 'next' || (/\bnext\b|next_page|next-page|pagenext/.test(ids) && !/章/.test(t));
  });
}
function nextContentPage(doc, url) {
  return nextLink(doc, url, url, function (t) { return /下一?[页頁]/.test(t) && !/章/.test(t); });
}

var CONTENT_SELECTORS = '#content, #chaptercontent, #chapter_content, #chapterContent, #txtContent, #booktxt, #nr1, #nr, #txt, .content, .txtnav, .read-content, .chapter-content, article, main, [class*="content"], [id*="content"], [class*="article"], [class*="yuedu"], [class*="txt"]';
// the candidate with the most text of its own (links count against it: a wrapper holding the navigation loses to the text block)
function contentBlock(doc) {
  var els = doc.querySelectorAll(CONTENT_SELECTORS), best = null, bestScore = 0;
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    if (/^(script|style|noscript|head|html|body)$/i.test(el.tagName)) continue;
    var as = el.querySelectorAll('a'), linkText = 0;
    for (var j = 0; j < as.length; j++) linkText += (as[j].textContent || '').length;
    var score = (el.textContent || '').replace(/\s+/g, '').length - linkText * 3;
    if (score > bestScore) { bestScore = score; best = el; }
  }
  return bestScore >= 100 ? best : null;
}

// ---------------------------------------------------------------------------------------------------------------------------------
// the page functions

async function search(key, page) {
  if (page > 1 || !/^https?:\/\//i.test(key || '')) return '[]';
  try {
    var b = JSON.parse(await info(key));
    return JSON.stringify(b && b.name ? [b] : []);
  } catch (e) {
    return '[]';
  }
}

async function info(bookurl) {
  var html = await flutterBridge.webview(bookurl, '', '', '', headers(bookurl.replace(/,\{[^{}]+\}$/, '')));
  return getinfo(html, bookurl);
}

async function getinfo(html, bookurl) {
  var base = bookurl.replace(/,\{[^{}]+\}$/, '');
  pages[bookurl] = html;
  flutterBridge.text(1, html);
  try {
    var doc = parse(html);
    remove(doc, 'script, style, noscript, iframe');
    var rawText = doc.body ? doc.body.innerText || doc.body.textContent || '' : '';
    var text = squeeze(rawText);

    var name = meta(doc, ['meta[property$="book_name"]', 'meta[name$="book_name"]', 'meta[property="og:title"]']);
    if (!name) {
      var title = doc.querySelector('title');
      if (title) name = cleanTitle(title.textContent);
    }
    name = squeeze(name).replace(/^《|》$/g, '');
    name = pickHeading(doc, name);
    var m = (rawText || '').match(/《([^《》\n]{1,40})》/);
    if (!name && m) name = m[1];

    var author = meta(doc, ['meta[property$="author"]', 'meta[name="author"]']);
    if (!author) author = field(text, '作\\s*[者家]', 20);
    if (!author) {
      var w = text.match(/([一-龥A-Za-z0-9·]{1,20})\s*著(?![a-z一-龥])/);
      if (w) author = w[1];
    }
    if (!author) author = textOf(doc.querySelector('#author, .author, [class*="author"]'));
    author = cleanAuthor(author);

    var kind = meta(doc, ['meta[property$="category"]', 'meta[name$="category"]']) || field(text, '(?:分\\s*类|类\\s*[型别])', 12);
    var status = meta(doc, ['meta[property$="status"]', 'meta[name$="status"]']) || field(text, '状\\s*态', 8);
    // the detail page shows wordCount as 「n万字」: the page's 字数 when it has one, else the status as the original's page did
    var words = pickWords(text);
    var latest = pickLatest(doc, rawText);

    var intro = meta(doc, ['meta[property="og:description"]', 'meta[property$="description"]', 'meta[name="description"]']);
    if (!intro) intro = textOf(doc.querySelector('#intro, .intro, [class*="intro"], [id*="intro"], [class*="summary"], [class*="desc"]'));
    intro = cleanIntro(intro);

    var cover = pickCover(doc, name, base);

    var bookInfo = {
      name: name || '请自行修改书名',
      author: author || '',
      intro: intro,
      kind: kind || '',
      latestChapterTitle: latest || '',
      coverUrl: cover || '',
      tocUrl: bookurl,
      bookUrl: bookurl,
      wordCount: words || status || ''
    };
    flutterBridge.log('详情 ' + bookInfo.name + ' ' + bookInfo.author);
    return JSON.stringify(bookInfo);
  } catch (e) {
    flutterBridge.log('详情错误:' + e.message);
    return JSON.stringify({ name: '请自行修改书名', author: '', tocUrl: bookurl, bookUrl: bookurl });
  }
}

async function chapterPage(url, bookurl) {
  var html = pages[url];
  delete pages[url];
  if (!html) html = await flutterBridge.webview(url, '', '', '', headers(bookurl));
  flutterBridge.text(2, html);
  var doc = parse(html);
  var as = doc.querySelectorAll('a[href]'), links = [];
  for (var i = 0; i < as.length; i++) {
    var a = as[i], href = a.getAttribute('href') || '';
    if (/^(javascript:|#|mailto:|tel:)/i.test(href)) continue;
    var u = absUrl(href, url), t = squeeze(a.textContent);
    if (!isChapterHref(u, url) || !isChapterText(t)) continue;
    links.push({ name: t, chapterId: u });
  }
  var prefix = mainPrefix(links.map(function (c) { return c.chapterId; }));
  if (prefix) links = links.filter(function (c) { return c.chapterId.indexOf(prefix) === 0; });
  flutterBridge.log('目录页 ' + url + ' ' + links.length + ' 条' + (prefix ? ' (' + prefix + ')' : ''));
  return { links: links, next: nextTocPage(doc, url) };
}

async function chapter(tocUrl, bookurl) {
  var all = [], visited = {}, next = tocUrl, n = 0;
  while (next && n < 50 && !visited[next]) {
    visited[next] = true;
    n++;
    var page;
    try {
      page = await chapterPage(next, bookurl);
    } catch (e) {
      flutterBridge.log('目录错误:' + e.message);
      break;
    }
    all = all.concat(page.links);
    next = page.next;
  }
  // a link listed twice (the 「最新章节」 block above the full list) keeps its last place
  var seen = {}, out = [];
  for (var i = all.length - 1; i >= 0; i--) {
    if (seen[all[i].chapterId]) continue;
    seen[all[i].chapterId] = true;
    out.push(all[i]);
  }
  out.reverse();
  try { await cache.set(TOC_KEY + bookurl, JSON.stringify(out.map(function (c) { return c.chapterId; }))); } catch (e) {}
  flutterBridge.log('目录 ' + out.length + ' 章');
  return JSON.stringify(out);
}

async function contentPage(url, bookurl) {
  var html = await flutterBridge.webview(url, '', '', '', headers(bookurl));
  flutterBridge.text(3, html);
  var doc = parse(html);
  remove(doc, 'script, style, noscript, iframe');
  var block = contentBlock(doc);
  var inner = block ? block.innerHTML : (doc.body ? doc.body.innerHTML : html);
  var text = await flutterBridge.htmlToText('<div>' + inner + '</div>');
  return { text: filterContentLines(text), next: nextContentPage(doc, url) };
}

async function content(url, bookurl) {
  var toc = {};
  try {
    var list = JSON.parse((await cache.get(TOC_KEY + bookurl)) || '[]');
    if (list && list.forEach) list.forEach(function (u) { toc[u] = true; });
  } catch (e) {}
  var parts = [], visited = {}, next = url, n = 0;
  while (next && n < 20 && !visited[next]) {
    visited[next] = true;
    n++;
    var page;
    try {
      page = await contentPage(next, bookurl);
    } catch (e) {
      flutterBridge.log('正文错误:' + e.message);
      break;
    }
    if (page.text) parts.push(page.text);
    next = page.next;
    if (next && toc[next]) break;
  }
  return parts.join('\n');
}
</script>
</html>
''';
