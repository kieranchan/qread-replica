// 七猫中文网 (qimao.com): a free-reading platform whose web site calls its own JSON API without signatures
// (2026-10-29): search `qimaoapi/api/search/result?keyword=&page=`, book `qimaoapi/api/book-detail/main-info?book_id=`,
// chapters `qimaoapi/api/book/chapter-list?book_id=&page=` (100 per page); chapter text is server-rendered on the
// reader page `/shuku/<book_id>-<chapter_id>/` (h2.chapter-title, div.article > p). Free tier.
import { createClient, UA_DESKTOP, text, find, all } from './http.mjs';

const BASE = 'https://www.qimao.com';
const API = `${BASE}/qimaoapi/api`;

const str = (v) => (v == null ? '' : String(v));

/** A unix timestamp (seconds or milliseconds) as YYYY-MM-DD, '' when it is not one. */
function dateOf(v) {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return '';
  const d = new Date(n * (String(Math.trunc(n)).length > 10 ? 1 : 1000));
  return Number.isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
}

/** Search items use category2_name / is_over_txt; main-info uses category_2_name / is_over and a datetime text. */
export function bookOf(b) {
  const cat = str(b.category2_name ?? b.category_2_name ?? b.category_name ?? b.category_1_name ?? b.category);
  const over = str(b.is_over);
  const upd = str(b.update_time);
  return {
    id: str(b.book_id ?? b.id),
    name: text(str(b.title ?? b.book_name)),
    author: str(b.author),
    intro: text(str(b.intro ?? b.description)),
    cover: str(b.image_link ?? b.free_image_link),
    category: cat,
    tags: [cat].filter(Boolean),
    status: str(b.is_over_txt) || (over === '1' ? '完结' : over === '0' ? '连载中' : ''),
    score: str(b.score ?? ''),
    wordCount: /万/.test(str(b.words_num)) ? str(b.words_num) : str(b.words_num) ? `${b.words_num}万字` : '',
    latestChapter: str(b.latest_chapter_title),
    updatedAt: /^\d{4}-\d{2}-\d{2}/.test(upd) ? upd.slice(0, 10) : dateOf(upd),
    url: str(b.read_url) || `${BASE}/shuku/${str(b.book_id ?? b.id)}/`,
    copyright: '来源：七猫中文网（免费阅读平台）',
  };
}

export function parseReader(html) {
  const title = text(find(html, /<h2[^>]*class="[^"]*chapter-title[^"]*"[^>]*>([\s\S]*?)<\/h2>/));
  const body = find(html, /<div[^>]*class="[^"]*\barticle\b[^"]*"[^>]*>([\s\S]*?)<\/div>/);
  const paras = all(body, /<p[^>]*>([\s\S]*?)<\/p>/).map((g) => text(g[0])).filter(Boolean);
  return { title, content: paras.join('\n') };
}

export function qimaoAdapter({ fetchImpl = null, minIntervalMs = 300 } = {}) {
  const client = createClient({ ua: UA_DESKTOP, referer: BASE + '/', minIntervalMs, fetchImpl });
  async function api(path, params) {
    const u = `${API}${path}?${new URLSearchParams(params)}`;
    const r = await client.get(u, { accept: 'application/json, text/plain, */*' });
    let j;
    try {
      j = JSON.parse(r.text);
    } catch {
      throw new Error(`七猫接口返回异常：${r.text.slice(0, 80)}`);
    }
    if (j.errors) throw new Error(`七猫：${j.errors.title ?? j.errors.details ?? '请求失败'}`);
    return j.data ?? j;
  }
  return {
    name: '七猫',
    tabs: ['小说'],
    tier: 'free',
    async search(key, page) {
      const d = await api('/search/result', { keyword: key, page: String(page) });
      const list = d.search_list?.length ? d.search_list : d.all_search_list ?? [];
      return list.map(bookOf).filter((b) => b.id);
    },
    async detail(id) {
      const d = await api('/book-detail/main-info', { book_id: id });
      const b = d.book_detail ?? d.book ?? d;
      let intro = '';
      try {
        const i = await api('/book-detail/intro', { book_id: id });
        intro = str(i.intro ?? i.book_intro ?? '');
      } catch {}
      return bookOf({ ...b, book_id: id, intro: intro || b.intro });
    },
    async catalog(id) {
      const out = [];
      const seen = new Set();
      for (let page = 1; page <= 100; page++) {
        const d = await api('/book/chapter-list', { book_id: id, page: String(page) });
        const chapters = d.chapters ?? d.chapter_list ?? [];
        let added = 0;
        for (const c of chapters) {
          const cid = str(c.id ?? c.chapter_id);
          if (!cid || seen.has(cid)) continue;
          seen.add(cid);
          added++;
          out.push({ id: `${id}/${cid}`, title: text(str(c.title)), isVip: str(c.is_vip) === '1', wordCount: str(c.words), time: dateOf(c.update_time) });
        }
        if (!added || chapters.length < 100) break;
      }
      return out;
    },
    async content(id) {
      const [bid, cid] = String(id).split('/');
      if (!cid) return { title: '', content: '' };
      const r = await client.get(`${BASE}/shuku/${bid}-${cid}/`);
      const c = parseReader(r.text);
      if (!c.content) throw new Error('七猫没有返回正文（可能是付费章节或页面改版）');
      return c;
    },
    async discover() {
      return [{ title: '七猫没有公开的榜单接口，请用搜索', key: '' }];
    },
  };
}
