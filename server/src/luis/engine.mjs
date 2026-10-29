// 路易斯 (Luis) — the owner's own aggregation platform behind a 时光源 page, wire-compatible with the protocol of the
// 大灰狼 service that `sources/langge` talks to (analysis/sources/langge/ANALYSIS.md): the page calls
// {server}/search | /detail | /catalog | /content | /discovestyle | /get_discover | /sources/config | /get_avatar
// and the engine fans the work out to platform adapters (one per upstream site), gates them by membership tier,
// caches answers in SQLite and reports per-adapter timings like the original (`source_time_cost`).
//
// An adapter is a plain object:
//   { name: '维基文库', tabs: ['小说'], tier: 'free' | 'vip' | 'svip',
//     search(key, page, tab) -> [book], detail(id, tab) -> book, catalog(id, tab) -> [chapter], content(itemId, tab) -> {title, content},
//     discover?(tab, gender) -> [{title, key, width?}], discoverList?(key, page, tab, gender) -> [book] }
// book: {id, name, author, intro, cover, status, score, wordCount, tags, category, latestChapter, updatedAt, role}
// chapter: {id, title, isPay, isVolume, wordCount, time}; content: text with newlines (audio / video: the media url).
import { ApiError, CODE } from '../util.mjs';

export const TIER_RANK = { free: 0, vip: 1, svip: 2 };

export const b64u = {
  enc: (s) => Buffer.from(String(s ?? ''), 'utf8').toString('base64url'),
  dec: (s) => {
    try {
      return Buffer.from(String(s ?? '').trim(), 'base64url').toString('utf8');
    } catch {
      return '';
    }
  },
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS luis_cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS luis_cache_exp ON luis_cache(expires_at);
CREATE TABLE IF NOT EXISTS luis_stats (
  day TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, user_id, kind)
);
`;

/** Creates the engine's tables (the admin CLI runs without an engine). */
export function ensureLuisSchema(db) {
  db.exec(SCHEMA);
}

const TTL = { search: 10 * 60_000, detail: 30 * 60_000, catalog: 30 * 60_000, content: 7 * 24 * 3600_000, discover: 60 * 60_000 };

function withTimeout(promise, ms, what) {
  let t;
  return Promise.race([promise, new Promise((_, rej) => (t = setTimeout(() => rej(new Error(`${what} 超时 (${ms} ms)`)), ms)))]).finally(() => clearTimeout(t));
}

const str = (v) => (v == null ? '' : String(v));

export class LuisEngine {
  constructor({ db, cfg, svc, adapters = [], now = Date.now, searchTimeoutMs = 15000, callTimeoutMs = 30000 }) {
    this.db = db;
    this.cfg = cfg;
    this.svc = svc;
    this.now = now;
    this.searchTimeoutMs = searchTimeoutMs;
    this.callTimeoutMs = callTimeoutMs;
    this.adapters = new Map();
    for (const a of adapters) this.register(a);
    db.exec(SCHEMA);
    this._sets = 0;
  }

  register(adapter) {
    if (!adapter?.name || typeof adapter.search !== 'function') throw new Error('adapter needs name and search()');
    this.adapters.set(adapter.name, { tabs: ['小说'], tier: 'free', ...adapter });
  }

  /** The platform's public address (the page's `server`). */
  get base() {
    return `${this.cfg.baseUrl}/luis`;
  }

  // ---------------- cache ----------------
  cacheGet(key) {
    const row = this.db.prepare('SELECT value, expires_at FROM luis_cache WHERE key = ?').get(key);
    if (!row || row.expires_at < this.now()) return null;
    try {
      return JSON.parse(row.value);
    } catch {
      return null;
    }
  }

  cacheSet(key, value, ttlMs) {
    this.db.prepare('INSERT OR REPLACE INTO luis_cache(key, value, expires_at) VALUES (?, ?, ?)').run(key, JSON.stringify(value), this.now() + ttlMs);
    if (++this._sets % 200 === 0) this.db.prepare('DELETE FROM luis_cache WHERE expires_at < ?').run(this.now());
  }

  cacheClear() {
    this.db.prepare('DELETE FROM luis_cache').run();
  }

  count(user, kind) {
    if (!user) return;
    const day = new Date(this.now()).toISOString().slice(0, 10);
    this.db.prepare('INSERT INTO luis_stats(day, user_id, kind, n) VALUES (?, ?, ?, 1) ON CONFLICT(day, user_id, kind) DO UPDATE SET n = n + 1').run(day, user.id, kind);
  }

  stats(user) {
    const day = new Date(this.now()).toISOString().slice(0, 10);
    const today = this.db.prepare('SELECT COALESCE(SUM(n), 0) AS n FROM luis_stats WHERE user_id = ? AND day = ? AND kind = ?').get(user.id, day, 'content').n;
    const all = this.db.prepare('SELECT COALESCE(SUM(n), 0) AS n FROM luis_stats WHERE user_id = ? AND kind = ?').get(user.id, 'content').n;
    return { today, all };
  }

  // ---------------- tiers ----------------
  tierOf(user) {
    if (!user) return 'free';
    return this.svc.isVip(user, this.now()) ? 'svip' : 'vip';
  }

  allowed(adapter, user) {
    return TIER_RANK[adapter.tier ?? 'free'] <= TIER_RANK[this.tierOf(user)];
  }

  /** `/sources/config`: the adapters by tier, and the tabs each one serves (the page's 平台 lists come from `modes`). */
  sourcesConfig() {
    const out = { free: [], vip: [], svip: [], modes: {} };
    for (const a of this.adapters.values()) {
      out[a.tier ?? 'free'].push(a.name);
      out.modes[a.name] = [...a.tabs];
    }
    return out;
  }

  adapter(name, user, tab) {
    const a = this.adapters.get(str(name).replace(/^svip_/, ''));
    if (!a) throw new ApiError(CODE.ERR, `未知平台：${name}`);
    if (tab && !a.tabs.includes(tab)) throw new ApiError(CODE.ERR, `${a.name} 不提供${tab}`);
    if (!this.allowed(a, user)) throw new ApiError(CODE.NEED_VIP, a.tier === 'svip' ? `${a.name} 需要会员，请在用户中心开通` : `${a.name} 需要登录`);
    return a;
  }

  // ---------------- normalisation (the wire names of the original) ----------------
  book(a, b, tab) {
    return {
      book_name: str(b.name),
      book_id: b64u.enc(b.id),
      author: str(b.author),
      score: str(b.score ?? '0'),
      status: str(b.status),
      word_number: str(b.wordCount),
      last_chapter_update_time: str(b.updatedAt),
      last_chapter_title: str(b.latestChapter),
      latest_chapter_title: str(b.latestChapter),
      category: str(b.category),
      tags: str(Array.isArray(b.tags) ? b.tags.join(',') : b.tags),
      abstract: str(b.intro),
      read_count: str(b.readCount ?? ''),
      read_count_all: '',
      thumb_url: str(b.cover),
      role: str(b.role),
      tab,
      source: a.name,
      book_url: str(b.url),
      toc_url: '',
    };
  }

  chapter(a, c, tab) {
    return {
      title: str(c.title),
      item_id: b64u.enc(c.id),
      first_pass_time: str(c.time),
      chapter_word_number: str(c.wordCount),
      source: a.name,
      tab,
      url: '',
      is_pay: !!c.isPay,
      is_volume: !!c.isVolume,
      toc_url: '',
    };
  }

  // ---------------- the calls ----------------
  async search({ key, page = 1, source = '全部', tab = '小说', user }) {
    key = str(key).trim();
    if (!key) throw new ApiError(CODE.ERR, '缺少关键字');
    page = Math.max(1, Number(page) || 1);
    const wanted = source === '全部' || !source ? [...this.adapters.keys()] : str(source).split(/[,，|]/).map((s) => s.trim().replace(/^svip_/, '')).filter(Boolean);
    const locked = [];
    const chosen = [];
    for (const name of wanted) {
      const a = this.adapters.get(name);
      if (!a || !a.tabs.includes(tab)) continue;
      if (!this.allowed(a, user)) locked.push(a.name);
      else chosen.push(a);
    }
    if (!chosen.length) {
      if (locked.length) throw new ApiError(CODE.NEED_VIP, `${locked.join('、')} 需要${locked.some((n) => this.adapters.get(n).tier === 'svip') ? '会员' : '登录'}`);
      throw new ApiError(CODE.ERR, `没有提供${tab}的平台`);
    }
    const cacheKey = `search:${tab}:${chosen.map((a) => a.name).join(',')}:${key}:${page}`;
    const cached = this.cacheGet(cacheKey);
    this.count(user, 'search');
    if (cached) return { ...cached, cache: true, disabled_sources: locked };
    const t0 = this.now();
    const results = await Promise.all(chosen.map(async (a) => {
      const s = this.now();
      try {
        const list = await withTimeout(Promise.resolve(a.search(key, page, tab)), this.searchTimeoutMs, a.name);
        const books = (Array.isArray(list) ? list : []).filter((b) => b && b.id != null).map((b) => this.book(a, b, tab));
        return { cost: { source: a.name, cacheData: false, timeCost: this.now() - s, resultCount: books.length }, books };
      } catch (e) {
        return { cost: { source: a.name, cacheData: false, timeCost: this.now() - s, resultCount: 0, error: String(e?.message ?? e) }, books: [] };
      }
    }));
    const out = {
      code: 0,
      msg: 'ok',
      cache: false,
      time: this.now() - t0,
      source_time_cost: results.map((r) => r.cost),
      disabled_sources: locked,
      data: results.flatMap((r) => r.books),
    };
    if (out.data.length) this.cacheSet(cacheKey, out, TTL.search);
    return out;
  }

  async detail({ bookId, source, tab = '小说', user }) {
    const a = this.adapter(source, user, tab);
    const id = b64u.dec(bookId);
    if (!id) throw new ApiError(CODE.ERR, '缺少 book_id');
    const cacheKey = `detail:${a.name}:${tab}:${id}`;
    const cached = this.cacheGet(cacheKey);
    if (cached) return { code: 0, msg: '', cache: true, data: cached };
    const t0 = this.now();
    const b = await withTimeout(Promise.resolve(a.detail(id, tab)), this.callTimeoutMs, `${a.name} 详情`);
    if (!b) throw new ApiError(CODE.NO_DATA, '没有这本书');
    const data = { ...this.book(a, { id, ...b }, tab), copyright_info: str(b.copyright), media: '', book_tts: '', book_tts_dice: null, book_review: '', relate_novel_book_id: '' };
    this.cacheSet(cacheKey, data, TTL.detail);
    return { code: 0, msg: '', cache: false, time: this.now() - t0, data };
  }

  async catalog({ bookId, source, tab = '小说', user }) {
    const a = this.adapter(source, user, tab);
    const id = b64u.dec(bookId);
    if (!id) throw new ApiError(CODE.ERR, '缺少 book_id');
    const cacheKey = `catalog:${a.name}:${tab}:${id}`;
    const cached = this.cacheGet(cacheKey);
    if (cached) return { code: 0, msg: '', cache: true, data: cached };
    const t0 = this.now();
    const list = await withTimeout(Promise.resolve(a.catalog(id, tab)), this.callTimeoutMs, `${a.name} 目录`);
    const data = (Array.isArray(list) ? list : []).map((c) => this.chapter(a, c, tab));
    if (data.length) this.cacheSet(cacheKey, data, TTL.catalog);
    return { code: 0, msg: '', cache: false, time: this.now() - t0, data };
  }

  async content({ itemId, source, tab = '小说', user }) {
    const a = this.adapter(source, user, tab);
    const id = b64u.dec(itemId);
    if (!id) throw new ApiError(CODE.ERR, '缺少 item_id');
    const cacheKey = `content:${a.name}:${tab}:${id}`;
    this.count(user, 'content');
    const cached = this.cacheGet(cacheKey);
    if (cached) return { code: 0, msg: '', cache: true, ...cached };
    const t0 = this.now();
    const r = await withTimeout(Promise.resolve(a.content(id, tab)), this.callTimeoutMs, `${a.name} 正文`);
    const out = typeof r === 'string' ? { title: '', content: r } : { title: str(r?.title), content: str(r?.content) };
    if (!out.content) throw new ApiError(CODE.NO_DATA, '获取内容失败：空正文');
    this.cacheSet(cacheKey, out, TTL.content);
    return { code: 0, msg: '', cache: false, time: this.now() - t0, ...out, contents: null };
  }

  /** `/discovestyle`: the entries of one platform's discovery page (lists become `/get_discover` urls). */
  async discover({ source, tab = '小说', gender = '男频', user }) {
    const a = this.adapters.get(str(source).replace(/^svip_/, '')) ?? [...this.adapters.values()].find((x) => x.tabs.includes(tab));
    if (!a) return { code: 0, msg: '', data: [] };
    const header = { title: `当前为: ${a.name} [${tab}] ${this.allowed(a, user) ? '' : a.tier === 'svip' ? '· 需要会员' : '· 需要登录'}`.trim(), url: '', style: { layout_flexGrow: 1, layout_flexBasisPercent: 1 } };
    if (typeof a.discover !== 'function') return { code: 0, msg: '', data: [header, { title: `${a.name} 没有发现页，请用搜索`, url: '', style: { layout_flexGrow: 1, layout_flexBasisPercent: 1 } }] };
    const cacheKey = `discover:${a.name}:${tab}:${gender}`;
    let entries = this.cacheGet(cacheKey);
    if (!entries) {
      entries = (await withTimeout(Promise.resolve(a.discover(tab, gender)), this.callTimeoutMs, `${a.name} 发现`)) ?? [];
      this.cacheSet(cacheKey, entries, TTL.discover);
    }
    const data = [header];
    for (const e of entries) {
      if (!e?.title) continue;
      if (!e.key) {
        data.push({ title: e.title, url: '', style: { layout_flexGrow: 1, layout_flexBasisPercent: 1 } });
        continue;
      }
      const u = `${this.base}/get_discover?source=${encodeURIComponent(a.name)}&tab=${encodeURIComponent(tab)}&bdtype=${encodeURIComponent(e.key)}&gender=${encodeURIComponent(gender)}&is_ranking=1&page={{page}}`;
      data.push({ title: e.title, url: u, style: { layout_flexGrow: 1, layout_flexBasisPercent: e.width === 1 ? 0.45 : 1 } });
    }
    return { code: 0, msg: '', data };
  }

  async discoverList({ source, tab = '小说', bdtype, gender = '男频', page = 1, user }) {
    const a = this.adapter(source, user, tab);
    if (typeof a.discoverList !== 'function') return { code: 0, msg: '', data: [] };
    page = Math.max(1, Number(page) || 1);
    const cacheKey = `discoverList:${a.name}:${tab}:${bdtype}:${gender}:${page}`;
    const cached = this.cacheGet(cacheKey);
    if (cached) return { code: 0, msg: '', cache: true, data: cached };
    const list = await withTimeout(Promise.resolve(a.discoverList(str(bdtype), page, tab, gender)), this.callTimeoutMs, `${a.name} 发现列表`);
    const data = (Array.isArray(list) ? list : []).filter((b) => b && b.id != null).map((b) => this.book(a, b, tab));
    if (data.length) this.cacheSet(cacheKey, data, TTL.search);
    return { code: 0, msg: '', cache: false, data };
  }
}
