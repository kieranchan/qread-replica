// A tiny novel site + a 时光源 page for it: the end-to-end test of the SDK and the runner without the network.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SDK = fs.readFileSync(path.join(HERE, '..', '..', 'sdk', 'qyd-sdk.js'), 'utf8');

export const BOOKS = [
  { id: 1, name: '测试之书', author: '作者甲', intro: '第一本书的简介', chapters: ['第一章 开始', '第二章 继续', '第三章 结束'] },
  { id: 2, name: '斗破测试', author: '作者乙', intro: '第二本书的简介', chapters: ['楔子', '第一章 废物'] },
];

const page = (body) => `<!doctype html><html><head><meta charset="utf-8"></head><body>${body}</body></html>`;

/** The source page: searches the fixture site, reads book / toc / chapter pages, and exercises cache, cookies and GBK. */
export const SOURCE_HTML = `<!doctype html><html><head><meta charset="utf-8"><title>fixture source</title></head><body></body>
<script>${SDK}</script>
<script>
const flutterBridge = new FlutterJSBridge();
const http = new Http(); const cache = new Cache(); const cookie = new Cookie();
const BASE = window.__base;
async function search(key, page, env) {
  await cache.set('lastKey', key);
  const gbk = await flutterBridge.utf8ToGbkUrlEncoded(key);
  const r = await http.Post(BASE + '/search', { 'X-Test': '1' }, 'q=' + gbk + '&page=' + page, '', true);
  flutterBridge.text(0, r.data);
  const doc = QYD.dom(r.data);
  return JSON.stringify(QYD.qa(doc, 'li.book').map(li => QYD.book({
    bookUrl: QYD.abs(BASE, QYD.attr(QYD.q(li, 'a'), 'href')), name: QYD.text(QYD.q(li, 'a')), author: QYD.text(QYD.q(li, '.author')),
    kind: ['测试', env], intro: QYD.text(QYD.q(li, '.intro')),
  })));
}
async function info(bookUrl) {
  const r = await http.Get(bookUrl, {}, true);
  const doc = QYD.dom(r.data);
  return JSON.stringify(QYD.book({ bookUrl, name: QYD.text(QYD.q(doc, 'h1')), author: QYD.text(QYD.q(doc, '.author')), intro: QYD.text(QYD.q(doc, '.intro')),
    tocUrl: QYD.abs(bookUrl, QYD.attr(QYD.q(doc, 'a.toc'), 'href')), wordCount: '12000', latestChapterTitle: QYD.text(QYD.q(doc, '.latest')) }));
}
async function chapter(tocUrl, bookUrl) {
  const r = await http.Get(tocUrl, {}, true);
  const doc = QYD.dom(r.data);
  return JSON.stringify(QYD.qa(doc, 'li a').map((a, i) => QYD.chapter({ name: QYD.text(a), chapterId: QYD.abs(tocUrl, QYD.attr(a, 'href')) }, i)));
}
async function content(url, bookUrl, index) {
  const r = await http.Get(url, {}, true);
  const doc = QYD.dom(r.data);
  const c = await cookie.getCookie(BASE, 'visited');
  return QYD.paragraphs(QYD.qa(doc, '#text p').map(QYD.text)) + '\\n<p>cookie=' + c + ' index=' + index + '</p>';
}
async function getfinds() {
  return JSON.stringify([QYD.explore.select('排序', ['最新', '最热'], (await cache.get('排序')) || '最新', "applySort()"), QYD.explore.list('全部', BASE + '/list?page={{page}}'), QYD.explore.title('分割')]);
}
async function applySort() { await cache.set('sort', await cache.get('排序')); await flutterBridge.refreshExplore(); return 'sorted'; }
async function find(url, page) {
  const r = await http.Get(url.replace('{{page}}', page), {}, true);
  const doc = QYD.dom(r.data);
  return JSON.stringify(QYD.qa(doc, 'li.book').map(li => QYD.book({ bookUrl: QYD.abs(BASE, QYD.attr(QYD.q(li, 'a'), 'href')), name: QYD.text(QYD.q(li, 'a')) })));
}
async function getloginurl() { return JSON.stringify([QYD.loginForm.text('用户名', 'u'), QYD.loginForm.password('密码')]); }
async function login() { const v = await cache.getLoginInfo(); return 'login:' + v; }
async function gethelp() { return '@html:<b>help</b>'; }
async function webtest() { return await flutterBridge.webview(BASE + '/js', 'document.title + ":" + document.querySelector("#dyn").textContent', '', '', '{}'); }
async function webhtml() { return await flutterBridge.webview(BASE + '/x', 'document.body.textContent', '<html><body>inline</body></html>', '', '{}'); }
async function webregex() { return await flutterBridge.webViewGetSource(BASE + '/js', '', '', '', '{}', 'asset\\\\.js'); }
async function callbackjs(event, book) { return event === 'clickBookName' ? 'true' : 'false'; }
</script></html>`;

/** Starts the fixture site; resolves { base, close }. The source page is served at /source.html. */
export function startFixture() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    const send = (body, type = 'text/html; charset=utf-8', headers = {}) => {
      res.writeHead(200, { 'Content-Type': type, ...headers });
      res.end(body);
    };
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      if (url.pathname === '/source.html') {
        return send(SOURCE_HTML.replace('window.__base', JSON.stringify(`http://127.0.0.1:${server.address().port}`)));
      }
      if (url.pathname === '/search' && req.method === 'POST') {
        // the keyword arrives GBK-encoded (utf8ToGbkUrlEncoded); decode it back
        const q = /q=([^&]*)/.exec(body)?.[1] ?? '';
        const bytes = Buffer.from(q.replace(/%([0-9A-F]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16))), 'latin1');
        const key = new TextDecoder('gb18030').decode(bytes);
        const hits = BOOKS.filter((b) => b.name.includes(key));
        const extra = req.headers['x-test'] === '1' ? '' : '<p>missing header</p>';
        return send(page(extra + '<ul>' + hits.map((b) => `<li class="book"><a href="/book/${b.id}">${b.name}</a><span class="author">${b.author}</span><span class="intro">${b.intro}</span></li>`).join('') + '</ul>'));
      }
      if (url.pathname === '/list') {
        return send(page('<ul>' + BOOKS.map((b) => `<li class="book"><a href="/book/${b.id}">${b.name}</a></li>`).join('') + '</ul>'));
      }
      const mb = /^\/book\/(\d+)$/.exec(url.pathname);
      if (mb) {
        const b = BOOKS.find((x) => x.id === Number(mb[1]));
        return send(page(`<h1>${b.name}</h1><span class="author">${b.author}</span><p class="intro">${b.intro}</p><span class="latest">${b.chapters.at(-1)}</span><a class="toc" href="/toc/${b.id}">目录</a>`), undefined, { 'Set-Cookie': 'visited=yes; Path=/' });
      }
      const mt = /^\/toc\/(\d+)$/.exec(url.pathname);
      if (mt) {
        const b = BOOKS.find((x) => x.id === Number(mt[1]));
        return send(page('<ul>' + b.chapters.map((c, i) => `<li><a href="/read/${b.id}/${i}">${c}</a></li>`).join('') + '</ul>'));
      }
      const mr = /^\/read\/(\d+)\/(\d+)$/.exec(url.pathname);
      if (mr) {
        const b = BOOKS.find((x) => x.id === Number(mr[1]));
        const gbk = Buffer.from(new TextEncoder().encode(''));
        return send(page(`<h2>${b.chapters[Number(mr[2])]}</h2><div id="text"><p>　　第一段 ${req.headers.cookie ?? ''}</p><p>第二段</p></div>`));
      }
      if (url.pathname === '/js') {
        return send('<html><head><title>dyn</title></head><body><div id="dyn">loading</div><script src="/asset.js"></script><script>setTimeout(() => { document.querySelector("#dyn").textContent = "ready"; }, 300);</script></body></html>');
      }
      if (url.pathname === '/asset.js') return send('window.assetLoaded = true;', 'application/javascript');
      res.writeHead(404);
      res.end('nope');
    });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ base: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) }));
  });
}
