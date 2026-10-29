// 维基文库 (zh.wikisource.org) adapter: public-domain Chinese works through the MediaWiki API. A work is a page whose
// wikitext links to its chapters as subpages (紅樓夢/第一回 …); single-page works have one chapter. Text comes back
// converted to simplified Chinese (`variant=zh-hans`). Free tier.
const API = 'https://zh.wikisource.org/w/api.php';
const UA = 'qread-luis/0.1 (+https://qread.forfine.me; personal reader)';

const CATEGORIES = [
  { title: '四大名著', key: 'list:紅樓夢|三國演義|水滸傳|西遊記' },
  { title: '章回小说', key: 'cat:章回小說' },
  { title: '笔记小说', key: 'cat:筆記小說' },
  { title: '志怪小说', key: 'cat:志怪小說' },
  { title: '清代小说', key: 'cat:清朝小說' },
  { title: '明代小说', key: 'cat:明朝小說' },
];

const DROP = /^(?:header.*|wst-header.*|headertemplate|ws-noexport|noprint|navbox.*|metadata|licenseContainer|licensetpl.*|textquality|mw-references-wrap|references|reference|dablink|hatnote|toc|mw-editsection|catlinks|printfooter|navigation-not-searchable|mw-empty-elt)$/i;
const DROP_TAGS = new Set(['div', 'table', 'span', 'sup', 'ol', 'ul', 'section', 'aside', 'nav', 'figure']);
const NAV_WORDS = /^(?:回目[录錄]|目[录錄]|[上下]一[回章卷篇节節集]|返回|首頁|首页|[\s·|│丨\-—·、←→«»↑]+)+$/;

/** Removes the elements (with everything nested in them) whose class or id marks navigation, licence or reference boxes. */
export function removeBlocks(html) {
  const re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>/g;
  let out = '';
  let last = 0;
  let skipTag = '';
  let depth = 0;
  let m;
  while ((m = re.exec(html))) {
    const [tag, close, rawName, attrs] = m;
    const name = rawName.toLowerCase();
    if (skipTag) {
      if (name === skipTag) {
        if (close) {
          depth--;
          if (depth === 0) {
            skipTag = '';
            last = m.index + tag.length;
          }
        } else if (!/\/\s*$/.test(attrs)) depth++;
      }
      continue;
    }
    if (!close && DROP_TAGS.has(name) && !/\/\s*$/.test(attrs)) {
      const cls = /\bclass\s*=\s*"([^"]*)"/i.exec(attrs)?.[1] ?? '';
      const id = /\bid\s*=\s*"([^"]*)"/i.exec(attrs)?.[1] ?? '';
      if (cls.split(/\s+/).some((c) => c && DROP.test(c)) || (id && DROP.test(id))) {
        out += html.slice(last, m.index);
        skipTag = name;
        depth = 1;
      }
    }
  }
  if (!skipTag) out += html.slice(last);
  return out;
}

/** Drops leading / trailing paragraphs that only hold navigation links (回目录 · 下一回). */
function dropNavParagraphs(html) {
  const text = (p) => p.replace(/<[^>]+>/g, '').replace(/&nbsp;|&#160;/g, ' ').trim();
  let h = html;
  for (let i = 0; i < 3; i++) {
    const lead = /^\s*(?:<hr[^>]*>\s*)*<p[^>]*>((?:(?!<\/p>)[\s\S])*)<\/p>\s*(?:<hr[^>]*>\s*)*/i.exec(h);
    if (lead && (text(lead[1]) === '' || NAV_WORDS.test(text(lead[1])))) h = h.slice(lead[0].length);
    else break;
  }
  for (let i = 0; i < 3; i++) {
    const tail = /(?:<hr[^>]*>\s*)*<p[^>]*>((?:(?!<\/p>)[\s\S])*)<\/p>\s*(?:<hr[^>]*>\s*)*$/i.exec(h);
    if (tail && (text(tail[1]) === '' || NAV_WORDS.test(text(tail[1])))) h = h.slice(0, tail.index);
    else break;
  }
  return h;
}

export function stripHtml(html) {
  let h = String(html ?? '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '');
  h = removeBlocks(h);
  // the references heading (its list went with mw-references-wrap), block wrappers, then the navigation paragraphs
  h = h
    .replace(/<h[1-6][^>]*>(?:\s|<[^>]+>)*(?:註釋|注释|注釋|註解|注解|參考文獻|参考文献|腳註|脚注|參見|参见|附註|附注)(?:\s|<[^>]+>)*<\/h[1-6]>/gi, '')
    .replace(/<table[\s\S]*?<\/table>/gi, '')
    .replace(/<\/?(?:div|section|article|main)\b[^>]*>/gi, '\n');
  h = dropNavParagraphs(h);
  return h
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|h[1-6]|dd|dt|tr)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;|&#160;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .split('\n')
    .map((l) => l.replace(/[ \t　]+$/g, '').replace(/^[ \t]+/, ''))
    .filter((l) => l.trim())
    .join('\n');
}

/**
 * The chapter links of a work's wikitext, in page order: [[Title/Sub|label]], the relative form [[/Sub|label]] and
 * {{:Title/Sub}} transclusions. A subpage linked several times (聊齋誌異 lists every story of a volume) counts once.
 */
export function chapterLinks(title, wikitext) {
  const out = [];
  const seen = new Set();
  const esc = title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`\\[\\[\\s*:?(?:(${esc})\\/|(\\/))([^|\\]#]+)(?:#[^|\\]]*)?(?:\\|([^\\]]*))?\\]\\]|\\{\\{\\s*:${esc}\\/([^|}]+)\\s*(?:\\|[^}]*)?\\}\\}`, 'g');
  let m;
  while ((m = re.exec(wikitext))) {
    const sub = (m[3] ?? m[5]).trim().replace(/_/g, ' ').replace(/\/+$/, '');
    if (!sub) continue;
    const page = `${title}/${sub}`;
    if (seen.has(page)) continue;
    seen.add(page);
    const label = (m[4] ?? '').replace(/<[^>]+>/g, '').replace(/[\s　]+/g, ' ').trim() || sub;
    out.push({ id: page, title: label });
  }
  return out;
}

/** A {{versions}} page: the editions it links to (titles that start with the work's title, or any page link when none do). */
export function editionLinks(title, wikitext) {
  if (!/\{\{\s*versions/i.test(wikitext)) return [];
  const out = [];
  const seen = new Set();
  const re = /\[\[\s*:?([^|\]#/:]+)(?:#[^|\]]*)?(?:\|([^\]]*))?\]\]/g;
  let m;
  while ((m = re.exec(wikitext))) {
    const page = m[1].trim().replace(/_/g, ' ');
    if (page === title || seen.has(page) || /^(Category|Author|作者|File|Portal|w|wikipedia|zh|en)$/i.test(page.split(':')[0]) && page.includes(':')) continue;
    seen.add(page);
    out.push({ id: page, title: page });
  }
  const same = out.filter((e) => e.id.startsWith(title));
  return (same.length ? same : out).slice(0, 8);
}

/** A field of the header template; links and templates reduced to their text. */
function headerField(wikitext, name) {
  // inner templates first (their `}}` would end the field early): 多名作者 becomes the names, the others go
  const flat = String(wikitext)
    .replace(/\{\{多名作者\|([^{}]*)\}\}/g, (_, args) => args.split('|').filter((_, i) => i % 3 === 1).join('、'))
    .replace(/\{\{(?!\s*(?:header|versions|Header|Versions)\b)[^{}]*\}\}/g, '');
  const m = new RegExp(`\\|\\s*${name}\\s*=\\s*([\\s\\S]*?)(?=\\n\\s*\\||\\}\\})`).exec(flat);
  if (!m) return '';
  return m[1]
    .replace(/\[\[([^\]|]*\|)?([^\]]*)\]\]/g, '$2')
    .replace(/<[^>]+>/g, '')
    .replace(/'{2,}/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** A short intro: the first text lines of the page body (header templates and link lists removed). */
function introOf(wikitext) {
  const body = wikitext
    .replace(/\{\{[^{}]*(\{\{[^{}]*\}\}[^{}]*)*\}\}/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/g, '$1')
    .replace(/^[*#:;=].*$/gm, '')
    .replace(/'{2,}/g, '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 8);
  return body.slice(0, 3).join('\n').slice(0, 400);
}

export function wikisourceAdapter({ fetchImpl = fetch, timeoutMs = 20000 } = {}) {
  async function api(params) {
    const u = API + '?' + new URLSearchParams({ format: 'json', formatversion: '2', ...params });
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const r = await fetchImpl(u, { headers: { 'User-Agent': UA, Accept: 'application/json' }, signal: ctl.signal });
      if (!r.ok) throw new Error(`维基文库 HTTP ${r.status}`);
      const j = await r.json();
      if (j.error) throw new Error(`维基文库: ${j.error.info ?? j.error.code}`);
      return j;
    } finally {
      clearTimeout(t);
    }
  }

  async function wikitext(title) {
    const j = await api({ action: 'parse', page: title, prop: 'wikitext', redirects: '1' });
    return { text: j.parse?.wikitext ?? '', title: j.parse?.title ?? title };
  }

  function work(title) {
    return { id: title, name: title.split('/')[0], author: '', intro: '', status: '已完结', category: '古典文学' };
  }

  const VOLUME = /^(?:第?[0-9０-９零一二三四五六七八九十百]+[卷册冊部編编集輯辑]|[上中下][卷册冊部編编集]|卷[0-9０-９零一二三四五六七八九十百]+)/;

  /**
   * Chapters of one page. When most subpages are volumes (第一卷, 卷二, 上卷 …) each volume is expanded one level: a volume
   * header followed by the chapters its page links to; other subpages (序, 作者小傳) stay as they are.
   */
  async function chaptersOf(title, text) {
    const links = chapterLinks(title, text);
    const volumes = links.filter((c) => VOLUME.test(c.id.slice(title.length + 1)));
    if (!links.length || links.length > 60 || volumes.length < Math.max(2, links.length / 2)) return links;
    const out = [];
    for (const c of links) {
      if (!VOLUME.test(c.id.slice(title.length + 1))) {
        out.push(c);
        continue;
      }
      const v = await wikitext(c.id);
      let sub = chapterLinks(v.title, v.text);
      // a volume written as one page with == headings == (聊齋志異/第01卷): every top-level section is a chapter
      if (!sub.length && (v.text.match(/^==[^=].*==\s*$/gm) ?? []).length >= 2) {
        const j = await api({ action: 'parse', page: v.title, prop: 'sections', redirects: '1' });
        sub = (j.parse?.sections ?? []).filter((s) => Number(s.toclevel) === 1 && s.index && /^\d+$/.test(String(s.index)))
          .map((s) => ({ id: `${v.title}#sec=${s.index}`, title: String(s.line).replace(/<[^>]+>/g, '').trim() }));
      }
      out.push({ id: c.id, title: c.title, isVolume: sub.length > 0 });
      out.push(...sub);
    }
    return out;
  }

  return {
    name: '维基文库',
    tabs: ['小说'],
    tier: 'free',

    async search(key, page) {
      const j = await api({ action: 'query', list: 'search', srsearch: key, srlimit: '30', sroffset: String((page - 1) * 30), srnamespace: '0', srprop: 'snippet' });
      const seen = new Set();
      const out = [];
      for (const r of j.query?.search ?? []) {
        const title = r.title.split('/')[0];
        if (seen.has(title)) continue;
        seen.add(title);
        out.push({ ...work(title), intro: stripHtml(r.snippet ?? '').replace(/\n/g, ' ') });
      }
      return out;
    },

    async detail(id) {
      const { text, title } = await wikitext(id);
      const chapters = chapterLinks(title, text);
      const editions = chapters.length ? [] : editionLinks(title, text);
      const notes = headerField(text, 'notes');
      return {
        ...work(title),
        author: headerField(text, 'author') || headerField(text, 'override_author') || headerField(text, '作者'),
        intro: [notes, introOf(text)].filter(Boolean).join('\n') || `《${title}》 · 维基文库`,
        latestChapter: chapters.length ? chapters[chapters.length - 1].title : editions.length ? `${editions.length} 个版本` : '',
        wordCount: '',
        copyright: '来源：维基文库 zh.wikisource.org（公有领域文本），由路易斯整理',
        url: `https://zh.wikisource.org/wiki/${encodeURIComponent(title)}`,
      };
    },

    async catalog(id) {
      const { text, title } = await wikitext(id);
      let chapters = await chaptersOf(title, text);
      if (!chapters.length) {
        // a {{versions}} page: every edition becomes a volume with its chapters
        for (const e of editionLinks(title, text)) {
          const ed = await wikitext(e.id);
          const sub = await chaptersOf(ed.title, ed.text);
          chapters.push({ id: ed.title, title: e.title, isVolume: sub.length > 0 });
          chapters.push(...sub);
        }
      }
      if (!chapters.length) chapters = [{ id: title, title: '全文' }];
      return chapters;
    },

    async content(id) {
      // `Page#sec=N`: one section of a page (a story of a volume page)
      const sec = /^(.*)#sec=(\d+)$/.exec(id);
      // zh-hans converts to simplified Chinese (the site's variants are zh-hans / zh-hant; zh-cn is not applied)
      const params = { action: 'parse', page: sec ? sec[1] : id, prop: 'text', variant: 'zh-hans', redirects: '1', disabletoc: '1', disableeditsection: '1' };
      if (sec) params.section = sec[2];
      const j = await api(params);
      const html = j.parse?.text ?? '';
      const title = j.parse?.title ?? id;
      let text = stripHtml(html);
      if (sec) text = text.replace(/^[^\n]{1,40}\n/, (line) => (line.trim().length <= 20 ? '' : line));
      return { title: title.includes('/') ? title.slice(title.indexOf('/') + 1) : title, content: text };
    },

    async discover() {
      return CATEGORIES;
    },

    async discoverList(key, page) {
      if (key.startsWith('list:')) {
        const titles = key.slice(5).split('|');
        return page === 1 ? titles.map((t) => work(t)) : [];
      }
      if (key.startsWith('cat:')) {
        const j = await api({ action: 'query', list: 'categorymembers', cmtitle: `Category:${key.slice(4)}`, cmnamespace: '0', cmlimit: '50', cmsort: 'sortkey', cmstartsortkeyprefix: '' });
        const members = (j.query?.categorymembers ?? []).map((m) => m.title.split('/')[0]);
        const unique = [...new Set(members)];
        const start = (page - 1) * 20;
        return unique.slice(start, start + 20).map((t) => work(t));
      }
      return [];
    },
  };
}
