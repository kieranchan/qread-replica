// 起点中文网 through its mobile site m.qidian.com (the desktop site answers a WAF challenge page to scripts; the mobile
// site is server-rendered). Free chapters only: VIP chapters are listed but locked (the site does not send their text).
// Pages (2026-10-29): search /soushu/<key>.html (items with data-bid), book /book/<bid>/ (JSON-LD Book + og meta),
// catalog /book/<bid>/catalog/ (the whole list, volume bars between items), chapter /chapter/<bid>/<cid>/ (h1.title,
// div.content > p). The pages carry an x-waf-captcha script: requests are paced and a challenge answers as a failure.
import { createClient, UA_MOBILE, text, lines, find, all, decodeEntities } from './http.mjs';

const BASE = 'https://m.qidian.com';

export function parseSearch(html) {
  const out = [];
  const re = /<a[^>]*class="[^"]*_bookWrapper_[^"]*"[^>]*data-bid="(\d+)"[^>]*>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = re.exec(html))) {
    const [, bid, body] = m;
    const tags = all(body, /<div class="_tags_[^"]*">([\s\S]*?)<\/div>/).map((g) => all(g[0], /<p>([^<]*)<\/p>/).map((x) => x[0].trim()))[0] ?? [];
    out.push({
      id: bid,
      name: text(find(body, /<h2 class="_searchBookName_[^"]*">([\s\S]*?)<\/h2>/)),
      author: text(find(body, /<p class="_searchBookAuthor_[^"]*">([\s\S]*?)<\/p>/)),
      intro: text(find(body, /<p class="_searchBookDesc_[^"]*">([\s\S]*?)<\/p>/)),
      cover: abs(find(body, /data-src="([^"]+)"/) || find(body, /<img[^>]+src="([^"]+)"/)),
      category: tags[0] ?? '',
      status: tags[1] ?? '',
      wordCount: tags[2] ?? '',
      tags: tags.slice(0, 1),
    });
  }
  return out;
}

function abs(u) {
  return u.startsWith('//') ? 'https:' + u : u;
}

export function parseBook(html, bid) {
  let ld = {};
  for (const block of all(html, /<script type="application\/ld\+json">([\s\S]*?)<\/script>/)) {
    try {
      const j = JSON.parse(block[0]);
      const book = (j['@graph'] ?? [j]).find((x) => x['@type'] === 'Book');
      if (book) ld = book;
    } catch {}
  }
  const props = {};
  for (const p of ld.additionalProperty ?? []) if (p?.name) props[p.name] = p.value;
  const og = Object.fromEntries(all(html, /<meta (?:property|name)="(og:[a-z:_]+|description)" content="([^"]*)"/).map(([k, v]) => [k, decodeEntities(v)]));
  const desc = og.description ?? '';
  return {
    id: bid,
    name: ld.name ?? og['og:title'] ?? '',
    author: ld.author?.name ?? og['og:novel:author'] ?? '',
    intro: ld.description ?? '',
    cover: abs(ld.image ?? og['og:image'] ?? ''),
    category: ld.genre ?? og['og:novel:category'] ?? '',
    status: props['连载状态'] ?? og['og:novel:status'] ?? '',
    latestChapter: props['最新章节'] ?? find(desc, /最新章节:([^。]+)/),
    wordCount: find(html, /([\d.]+)\s*(?:<[^>]*>\s*)*万字/) ? `${find(html, /([\d.]+)\s*(?:<[^>]*>\s*)*万字/)}万字` : '',
    updatedAt: find(html, /datetime="([^"]+)"/),
    tags: [ld.genre ?? ''].filter(Boolean),
    url: `${BASE}/book/${bid}/`,
    copyright: '来源：起点中文网（免费章节）',
  };
}

/** The catalog list: volume bars (_chapterBar_) become volume headers, items are the chapter links. */
export function parseCatalog(html, bid) {
  const out = [];
  const seen = new Set();
  // the list starts after the header block (whose "最新章节" link would otherwise come first)
  const start = html.search(/class="y-list(?:__content)?"/);
  const list = start >= 0 ? html.slice(start) : html;
  const re = new RegExp(`<div class="_chapterBar_[^"]*">([^<]*)<\\/div>|<a([^>]*)href="(?:https?:)?\\/\\/m\\.qidian\\.com\\/chapter\\/${bid}\\/(\\d+)\\/"[^>]*>([\\s\\S]*?)<\\/a>`, 'g');
  let m;
  while ((m = re.exec(list))) {
    if (m[1] !== undefined) {
      const title = text(m[1]);
      if (title) out.push({ id: `${bid}/vol:${out.length}`, title, isVolume: true });
      continue;
    }
    if (/_secondHeader_/.test(m[2])) continue;
    const cid = m[3];
    if (cid === '0' || seen.has(cid)) continue;
    seen.add(cid);
    const body = m[4];
    // the title is the first text node; labels (免费 / VIP / 会员) and times are separate elements
    const title = text(body.replace(/<(i|svg|span|em|p|time)[^>]*>[\s\S]*?<\/\1>/gi, ' ')).replace(/\s*(?:免费|VIP|会员|付费)\s*$/, '').trim() || text(body);
    if (!title) continue;
    const locked = /lock|vip|订阅/i.test(body);
    out.push({ id: `${bid}/${cid}`, title, isVip: locked, isPay: locked, time: find(body, /(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}:\d{2})?)/) });
  }
  return out;
}

export function parseChapter(html) {
  const h1 = /<h1[^>]*class="[^"]*title[^"]*"[^>]*>([\s\S]*?)<\/h1>/.exec(html);
  const title = text(h1 ? h1[1] : '');
  // the text: the <p> of the content block after the title, up to the comments / recommendations that follow it
  let body = h1 ? html.slice(h1.index + h1[0].length) : html;
  const contentStart = body.search(/<div[^>]*class="[^"]*\bcontent\b[^"]*"[^>]*>/);
  if (contentStart >= 0) body = body.slice(contentStart);
  const end = body.search(/本章说|同人创作|class="[^"]*(?:comment|review|recommend|author-say|footer)[^"]*"/i);
  if (end > 0) body = body.slice(0, end);
  const paras = all(body, /<p[^>]*>([\s\S]*?)<\/p>/).map((g) => text(g[0])).filter(Boolean);
  const locked = !paras.length && /订阅|VIP章节|解锁|lock/i.test(html);
  return { title, content: paras.join('\n'), locked };
}

export function qidianAdapter({ fetchImpl = null, minIntervalMs = 600 } = {}) {
  const client = createClient({ ua: UA_MOBILE, referer: BASE + '/', minIntervalMs, fetchImpl });
  async function page(url) {
    const r = await client.get(url);
    if (r.status === 202 || /x-waf-captcha-referer[\s\S]{0,400}?<\/script>\s*<\/head>\s*<body>\s*<\/body>/i.test(r.text) || (r.text.length < 600 && /captcha|验证/i.test(r.text))) {
      throw new Error('起点返回了验证页，请稍后再试');
    }
    return r.text;
  }
  const split = (id) => {
    const [bid, rest] = String(id).split('/');
    return { bid, rest };
  };
  return {
    name: '起点',
    tabs: ['小说'],
    tier: 'free',
    async search(key, page) {
      if (page > 1) return [];
      return parseSearch(await page_(`${BASE}/soushu/${encodeURIComponent(key)}.html`));
    },
    async detail(id) {
      const { bid } = split(id);
      return parseBook(await page_(`${BASE}/book/${bid}/`), bid);
    },
    async catalog(id) {
      const { bid } = split(id);
      return parseCatalog(await page_(`${BASE}/book/${bid}/catalog/`), bid);
    },
    async content(id) {
      const { bid, rest } = split(id);
      if (!rest || rest.startsWith('vol:')) return { title: '', content: '' };
      const c = parseChapter(await page_(`${BASE}/chapter/${bid}/${rest}/`));
      if (!c.content && c.locked) throw new Error('VIP 章节需要在起点订阅，无法获取');
      return c;
    },
    async discover() {
      return [{ title: '起点没有公开的榜单页，请用搜索', key: '' }];
    },
  };
  function page_(url) {
    return page(url);
  }
}
