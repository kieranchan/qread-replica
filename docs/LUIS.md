# 路易斯 (Luis) — the owner's aggregation platform

路易斯 is the server side of a 聚合书源: a 时光源 page in the app (`sources/luis`) asks the platform for searches,
book details, tables of contents and chapter text, and the platform answers from **platform adapters** (one per
upstream site), gated by the account/membership system the server already has. The wire protocol is the one of the
大灰狼 service the owner subscribes to (`analysis/sources/langge/ANALYSIS.md`), so the page logic, the discovery
drop-downs and the login flow are the same; only the backend is ours.

```
app  ──时光源 page──▶  https://qread.forfine.me/luis/{search,detail,catalog,content,discovestyle,get_discover,sources/config,get_avatar}
                                │ cookies qttoken + deviceId  (set by /luis/login, the app keeps them)
                                ▼
                      server/src/luis/engine.mjs   tiers · fan-out · cache (SQLite) · ids · stats
                                │
                   adapters/wikisource.mjs (free)   adapters/library.mjs (svip, the owner's TXT books)   … more adapters
```

## Endpoints (`server/src/luis/api.mjs`)

| path | answers |
|---|---|
| `GET /luis/login?source_client=qyd` | login page; `POST /luis/login_api {username, password}` sets `qttoken` (HttpOnly, a normal session token of the account system) and `deviceId`, answers `{code, data:{username, isvip, vip, next}}` |
| `GET /luis/user` + `/luis/user_api` | user centre: membership, 密钥 (= qttoken), device, server, reading stats, platforms with tier and availability |
| `POST /luis/logout` | revokes the token, clears the cookie |
| `GET /luis/get_avatar` | `{code:0, email, nickname, avatar}`, HTTP 400 `{code:-2}` when not logged in (as the original) |
| `GET /luis/sources/config` | `{code:0, data:{free[], vip[], svip[], modes:{name:[tabs]}}}` |
| `GET /luis/search?title&page&source=全部\|名,名&tab` | `{code, msg, cache, time, source_time_cost[{source,timeCost,resultCount,error?}], disabled_sources[], data[]}` — `disabled_sources` = platforms this account may not use; a search limited to locked platforms answers `code -3` |
| `GET /luis/detail?book_id&source&tab` / `catalog` / `content?item_id` | `{code, msg, cache, data}` / `{code, data[]}` / `{code, title, content}`; failures are `code != 0` with a Chinese `msg` |
| `GET /luis/discovestyle?source&source_type&tab` → `GET /luis/get_discover?source&tab&bdtype&gender&page` | the platform's discovery entries (`style.layout_flexBasisPercent 0.45` = half width) and their lists |
| `GET /luis/api/system_info` | load / memory / uptime |

Auth: cookie `qttoken`, or `?qttoken=`, or header `x-tockenid`. An invalid token just means "not logged in". 240
requests per minute per IP; login attempts are rate limited like the account API.

Ids: `book_id` and `item_id` are base64url of the adapter's own ids (the original does the same), so they are
opaque to the page.

Tiers: `free` (no login), `vip` (any account), `svip` (membership: `users.vip_until` in the future, the same
flag the 会员中心 / activation codes manage). A member sees everything; the user centre shows a 未开通 tag on
platforms the account cannot use.

Cache (`luis_cache`): search 10 min, detail/catalog 30 min, content 7 days, discovery 1 h. `qread-admin
luis-cache-clear` empties it. `luis_stats` counts searches and chapters per user and day (user centre 今日阅读 /
累计).

## Adapters (`server/src/luis/adapters/`)

```js
export function myAdapter() {
  return {
    name: '站名', tabs: ['小说'], tier: 'free',                 // or 'vip' / 'svip'
    async search(key, page, tab) { return [{ id, name, author, intro, cover, status, latestChapter, wordCount, tags, category, updatedAt }]; },
    async detail(id, tab) { return { name, author, intro, cover, status, latestChapter, wordCount, tags, copyright, url }; },
    async catalog(id, tab) { return [{ id, title, isPay, isVolume, wordCount, time }]; },
    async content(itemId, tab) { return { title, content: 'line\nline' }; },   // audio / video tabs: the media url
    async discover(tab, gender) { return [{ title: '榜单', key: 'top', width: 1 }, { title: '分组标题' }]; },   // optional
    async discoverList(key, page, tab, gender) { return [book…]; },                                        // optional
  };
}
```
Register it in `defaultAdapters()` (`api.mjs`). The engine adds the timeout (15 s per adapter in a search, 30 s
otherwise), the cache, the tier gate and the wire names; an adapter that throws only marks its own entry in
`source_time_cost` (`error`), the others still answer. Tests inject adapters with `createApp({ luisAdapters })`.
Site adapters use `adapters/http.mjs`: one client per site with a minimum interval between requests, browser headers,
one retry with back-off, GB18030 decoding and small HTML helpers. The transport is `node:http(s)` with the lenient
header parser (undici's `fetch` rejects 七猫's responses) and gzip / br decoding; tests pass `fetchImpl` and get the
fetch path with fixtures (`test/luis_sites.test.mjs`).

* **起点** (`qidian.mjs`, free): the mobile site m.qidian.com (the desktop site answers a WAF challenge page to scripts).
  Search `/soushu/<key>.html` (items with `data-bid`), book `/book/<bid>/` (JSON-LD Book + og meta), catalog
  `/book/<bid>/catalog/` (volume bars become volume headers), chapter `/chapter/<bid>/<cid>/` (`h1.title`, `div.content > p`,
  cut before the comments). Free chapters only; locked ones are listed with `is_pay`. Paced at 600 ms per request with a
  mobile UA; a captcha page answers as a failure (`起点返回了验证页`).
* **七猫** (`qimao.mjs`, free): the site's own JSON API without signatures — `qimaoapi/api/search/result?keyword=&page=`,
  `book-detail/main-info?book_id=` + `book-detail/intro?book_id=`, `book/chapter-list?book_id=&page=` (100 per page);
  chapter text from the server-rendered reader page `/shuku/<book_id>-<chapter_id>/` (`h2.chapter-title`, `div.article > p`).
  The parameter must be `keyword` / `book_id` (other names answer empty lists or 请求参数错误).
* **晋江** (`jjwxc.mjs`, free): GB18030 pages — `search.php?kw=<gbk>&t=1`, `onebook.php?novelid=` (intro, 文章类型/进度/字数/标签,
  `tr[itemprop=chapter]` rows; VIP rows link to the vip page and are marked `is_pay`), chapter text in
  `div.noveltext > #paragraph_comment_content` (toolbar / bookmark widgets dropped, 作者有话说 appended when rendered).
* **维基文库** (`wikisource.mjs`, free): MediaWiki API of zh.wikisource.org. Search = full-text search with chapter
  pages folded into their work; catalog = the work page's subpage links in order (volume pages one level deep);
  content = the parsed page converted to simplified Chinese (`variant=zh-hans`; titles stay as written),
  navigation / licence / reference boxes stripped; `{{versions}}` pages list their editions as volumes, volume
  pages made of `== headings ==` (聊齋誌異) give one chapter per section (`Page#sec=N`); discovery = fixed lists and
  categories (章回小說, 筆記小說, 志怪小說, 清朝小說, 明朝小說).
* **路易斯书库** (`library.mjs`, svip): TXT files the owner uploads (`qread-admin luis-add-book <file.txt> --name N
  --author A [--intro] [--tags] [--category] [--cover] [--status]`; UTF-8 / UTF-16 / GB18030 detected; chapters
  split at 第N章/回/卷, 序章, 楔子, 番外 …; headings-less text every ~4000 characters). `luis-list-books`,
  `luis-remove-book <id>`.

## The page (`sources/luis`)
`source.src.html` + the SDK → `dist/source.json` (import file, page inline) and `dist/source.hosted.json`
(`html: https://qread.forfine.me/tsy/luis.html`, updated on the server with `qread-admin set-source luis
sources/luis/dist/source.html`). Drop-downs: 线路 (servers), 类型 (tabs the backend offers), 频道, 平台 (adapters of
the tab, from `/sources/config`), 搜索范围 (全部 or one platform); 「登录 / 账户」 opens `/luis/login`; 帮助 shows
server, account and the platform tiers. The platform list is read from the backend, so a new adapter appears in
the app without a page change.

## Verify / deploy
```bash
cd server && npm test                      # luis.test.mjs: engine, API, login/tiers, library, admin, adapters (fake MediaWiki)
cd sources/runner && npm test              # luis.test.mjs: the page in headless Chrome against the server in-process
node sources/runner/run.mjs --page https://qread.forfine.me/tsy/luis.html --base https://qread.forfine.me/tsy/luis \
     --cookie https://qread.forfine.me "qttoken=…" flow 红楼梦
server/deploy/deploy.sh && ssh … qread-admin set-source luis <sources/luis/dist/source.html>
```

## What is deliberately not here
番茄 (every API needs the `a_bogus` signature and chapter text is obfuscated through a custom font) and 书旗 (the sites
answer 403 to scripts; chapter URLs are app-signed): both would need adversarial work-arounds and were not built.
QQ阅读 is possible (Nuxt page state carries book details and free chapter text) but its search call and catalog API were
not found yet. Only chapters the platforms publish for free are ever served; VIP chapters are listed locked.
The evaluation with the probes is `analysis/luis/PLATFORMS-2026-10-29.md` (local only).
