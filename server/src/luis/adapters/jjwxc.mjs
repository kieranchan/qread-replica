// 晋江文学城 (jjwxc.net): GB18030 server-rendered pages. Search `search.php?kw=<gbk>&t=1`, book `onebook.php?novelid=`
// (intro, author, 文章进度/全文字数/内容标签, chapter table rows itemprop="chapter"), chapter `onebook.php?novelid=&chapterid=`
// (div.noveltext). VIP chapters are listed but locked (their link goes to the vip page). Free tier.
import { createClient, UA_DESKTOP, gbkEncode, text, lines, find, all, decodeEntities } from './http.mjs';

const BASE = 'https://www.jjwxc.net';

export function parseSearch(html) {
  const out = [];
  const parts = html.split(/<h3[^>]*class="title"[^>]*>/).slice(1);
  for (const part of parts) {
    const m = /onebook\.php\?novelid=(\d+)"[^>]*>([\s\S]*?)<\/a>/.exec(part);
    if (!m) continue;
    const id = m[1];
    const name = text(m[2]);
    const date = find(part, /\((\d{4}-\d{2}-\d{2})\)/);
    const rest = part.slice(m.index);
    const author = text(find(rest, /作者[:：]\s*(?:<[^>]+>\s*)*([^<]{1,30})/));
    const intro = text(find(rest, /<\/h3>([\s\S]*?)(?:作者[:：]|<h3)/)).replace(/^\(\d{4}-\d{2}-\d{2}\)\s*/, '');
    out.push({ id, name, author, intro: intro.slice(0, 300), updatedAt: date });
  }
  return out;
}

function field(html, label) {
  return text(find(html, new RegExp(label + '[:：]\\s*((?:<[^>]+>\\s*)*[^<]{0,80})')));
}

export function parseBook(html, id) {
  const title = decodeEntities(find(html, /<title>([^<]*)<\/title>/));
  const tm = /《([^》]+)》\s*([^_\s]+)/.exec(title);
  const name = tm ? tm[1] : text(find(html, /<span itemprop="articleSection">([^<]*)/)) || '';
  const intro = lines(find(html, /id="novelintro"[^>]*>([\s\S]*?)<\/div>/)).join('\n');
  const tagsRaw = find(html, /内容标签[:：]([\s\S]{0,400}?)<\/(?:div|span|td)>/);
  const tags = all(tagsRaw, />([^<>]{1,12})<\/a>/).map((g) => g[0].trim()).filter(Boolean);
  const keywords = decodeEntities(find(html, /<meta name="Keywords" content="([^"]*)"/i));
  return {
    id,
    name,
    author: text(find(html, /authorid=\d+"[^>]*>\s*(?:<span[^>]*>)?([^<]{1,30})/)) || (tm ? tm[2] : ''),
    intro,
    cover: find(html, /<img class="noveldefaultimage"[^>]*\ssrc="([^"]+)"/),
    category: field(html, '文章类型').replace(/\s+/g, ''),
    status: field(html, '文章进度') || '',
    wordCount: field(html, '全文字数').replace(/\s+/g, ''),
    tags: tags.length ? tags : (field(html, '内容标签') ? field(html, '内容标签').split(/\s+/) : []),
    latestChapter: '',
    updatedAt: find(keywords, /最新更新:(\d{4}-\d{2}-\d{2}[ \d:]*)/).trim(),
    url: `${BASE}/onebook.php?novelid=${id}`,
    copyright: '来源：晋江文学城（免费章节）',
  };
}

export function parseCatalog(html, id) {
  const out = [];
  const rows = all(html, /<tr[^>]*itemprop="chapter"[^>]*>([\s\S]*?)<\/tr>/);
  for (const [row] of rows) {
    const cells = all(row, /<td[^>]*>([\s\S]*?)<\/td>/).map((g) => g[0]);
    const link = /<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/.exec(cells[1] ?? '');
    const headline = text(link ? link[2] : cells[1] ?? '');
    const cid = find(link?.[1] ?? '', /chapterid=(\d+)/) || text(cells[0] ?? '');
    if (!cid) continue;
    const vip = !link || /vip/i.test(link[1]) || /vip/i.test(row);
    const sub = text(cells[2] ?? '');
    out.push({
      id: `${id}/${cid}`,
      title: sub ? `${headline} ${sub}` : headline,
      isVip: vip,
      isPay: vip,
      wordCount: text(cells[3] ?? ''),
      time: find(row, /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/),
    });
  }
  return out;
}

const TOOLBAR = /^(?:\[添加书签\]|\[\s*推荐给朋友\s*\]|\[投诉\]|投诉色情有害|投诉涉未成年有害|投诉数据造假|其他|文章收藏|为收藏文章分类|新增|取消|\+\s*新增收藏类别|定制收藏类别|查看收藏列表|插入书签|\s)+$/;

/**
 * The chapter text lives in `div.noveltext > div#paragraph_comment_content` (lines separated by <br>), the title in the
 * `<h2>` before it; the toolbar, bookmark and 作者有话说 widgets around it are not part of the text.
 */
export function parseChapter(html) {
  const box = find(html, /<div class="noveltext[^"]*"[^>]*>([\s\S]*?)<div id="note_danmu_wrapper"|<div class="noveltext[^"]*"[^>]*>([\s\S]*)/);
  const title = text(find(box, /<h2[^>]*>([\s\S]*?)<\/h2>/)) || text(find(html, /<title>([^<]*?)\s*[\^_]/));
  let body = find(box, /<div id="paragraph_comment_content"[^>]*>([\s\S]*?)<\/div>\s*<div id="favoriteshow/);
  if (!body) body = find(box, /<div id="paragraph_comment_content"[^>]*>([\s\S]*?)<\/div>/);
  if (!body) {
    // older layout: the text follows the <h2> block directly
    body = box.replace(/^[\s\S]*?<\/h2>\s*<br\s*\/?>\s*<\/div>/, '').replace(/<div align="right">[\s\S]*$/, '');
  }
  let out = lines(body).filter((l) => !TOOLBAR.test(l) && !/^displayyrt\(/.test(l));
  // 作者有话说 (when rendered server side) is appended as its own block
  const note = lines(find(html, /<div class="note_main"[^>]*>([\s\S]*?)<\/div>\s*<div class="recommend_novel_box"/)).filter((l) => !TOOLBAR.test(l));
  if (note.length) out = out.concat(['', '【作者有话说】', ...note]);
  return { title, content: out.join('\n').replace(/\n{3,}/g, '\n\n').trim() };
}

export function jjwxcAdapter({ fetchImpl = null, minIntervalMs = 500 } = {}) {
  const client = createClient({ ua: UA_DESKTOP, referer: BASE + '/', minIntervalMs, fetchImpl });
  const page = async (url) => (await client.get(url, { charset: 'gb18030' })).text;
  return {
    name: '晋江',
    tabs: ['小说'],
    tier: 'free',
    async search(key, page_) {
      if (page_ > 1) return [];
      return parseSearch(await page(`${BASE}/search.php?kw=${gbkEncode(key)}&t=1`));
    },
    async detail(id) {
      const nid = String(id).split('/')[0];
      return parseBook(await page(`${BASE}/onebook.php?novelid=${nid}`), nid);
    },
    async catalog(id) {
      const nid = String(id).split('/')[0];
      return parseCatalog(await page(`${BASE}/onebook.php?novelid=${nid}`), nid);
    },
    async content(id) {
      const [nid, cid] = String(id).split('/');
      if (!cid) return { title: '', content: '' };
      const html = await page(`${BASE}/onebook.php?novelid=${nid}&chapterid=${cid}`);
      if (/vip\.php|本章为VIP章节|需要购买/i.test(html) && !/class="noveltext/.test(html)) throw new Error('VIP 章节需要在晋江购买，无法获取');
      const c = parseChapter(html);
      if (!c.content) throw new Error('晋江没有返回正文（可能是VIP章节或页面改版）');
      return c;
    },
    async discover() {
      return [{ title: '晋江没有公开的榜单接口，请用搜索', key: '' }];
    },
  };
}
