# 时光源 (web-page book sources): the contract

A 时光源 is one HTML page. The app loads it into a hidden web view, waits until the page says it is ready, then calls
the page's global JavaScript functions (search, detail, table of contents, chapter text, discovery, login …) and
parses the JSON text they return. The page talks back to the app through
`window.flutter_inappwebview.callHandler(name, …args)` (HTTP, cache, cookies, toasts, browsers …).

This document is the complete contract as the replica implements it (`app/lib/util/source/`), recovered from the
original app (addresses in the file headers there) and validated against a real third-party source (大灰狼聚合书源,
see `analysis/sources/langge/ANALYSIS.md`). The authoring kit lives in `sources/` (`sdk/qyd-sdk.js`, the desktop
runner, a worked example).

## 1. The source record (import JSON)

```json
{"bookSourceUrl": "https://example.com/my-source", "bookSourceName": "示例", "bookSourceGroup": "分组",
 "html": "<!DOCTYPE html>… or https://host/path/source.html",
 "enabled": true, "enabledExplore": true, "login": false, "help": false, "customButton": false, "eventListener": false}
```

* `html`: the page code itself, or an `http(s)` URL the app downloads (30 s, header `deviceid`; the last copy is kept and
  used when the download fails). A page whose text starts with `@aes` is base64 + AES-CBC/PKCS7 with key = IV = the
  UTF-8 bytes of a 16-character constant (`--dart-define=QREAD_SOURCE_AES_KEY`).
* `bookSourceUrl`: the key of the source and the address the page is loaded under (relative URLs resolve against it;
  for a non-http value the page runs under `http://localhost/`). Cookies the app holds for it are pushed into the web view.
* `login`: show 登录 (the page's `getloginurl()`); `help`: show 帮助 (`gethelp()`); `customButton`: a round button on the
  detail page and in the reader (`callbackjs('clickCustomButton' | 'longClickCustomButton', book)`); `eventListener`:
  send the detail-page events of section 5.
* A record with Legado rule keys (`searchUrl`, `ruleSearch` …) or `isqread: true` is not a 时光源.

## 2. Lifecycle

1. The page is loaded (`loadData(html, baseUrl)`); the web view's `navigator.userAgent` becomes the app's UA.
2. The app waits for `callHandler('CookieJar', isCookieJar)` (60 s, `等待页面就绪超时`). `isCookieJar` false means: do not
   keep the cookies of the page's `http` answers. Pages opened in a *front* web view must not call it.
3. Every call runs `await fn(args)` inside the page; the value is JSON-encoded (numbers raw) and normalised: text as is,
   objects as JSON, nothing as `''`. A throwing function answers `''` and its message goes to the log.
4. One page per source stays alive; it is dropped after 5 idle minutes or when the source is edited
   (重载书源线程), and re-created on the next call.

## 3. Entry points (what the app calls) and timeouts

| call | answers | timeout |
|---|---|---|
| `search(key, page, env)` | JSON array of books; `env` is `search`, or `searchone` when this is the only source searched | 120 s |
| `info(bookUrl)` | one book (JSON object); the app keeps `bookUrl` and takes the other fields | 120 s |
| `chapter(tocUrl, bookUrl)` | JSON array of chapters (`tocUrl` = the book's `tocUrl`, or `bookUrl` when none; the app calls `info()` first when it only has a search result) | 400 s |
| `content(url, bookUrl, index)` | the chapter text (`url` = the chapter's `chapterId`); audio books / short dramas answer the media URL | 120 s |
| `getfinds()` | JSON array of discovery entries (section 4.3); cached under `ExploreUrl<bookSourceUrl>` until `refreshExplore` | 120 s |
| `find(url, page)` | JSON array of books of a discovery list (`{{page}}` is for the page to replace) | 120 s |
| `getloginurl()` | an `http(s)` / `data:text/html` URL (opened in the app's browser, its cookies are kept) or the JSON of a login form (section 4.4); `''` → `未获取到登录参数!` | 120 s |
| `login()` | runs after the login form was saved (`cache.get('LoginInfo')` holds the JSON of the fields) | 120 s |
| `gethelp()` | an `http(s)` URL, plain text, or `@html:…` | 20 s |
| `pay(bookUrl, chapterId)` | after the user chose 购买 on a `isPay` chapter; the app reloads toc and chapter afterwards | 120 s |
| `filter()` / `findfilter(url)` | 筛选 of a single-source search / of a discovery list: an http URL or a `data:` page to open, else nothing | 120 s |
| `imagedecrypt(url, base64)` | the decoded image bytes (array of ints) for images whose JSON options have `imageDecode` | 60 s |
| `shouldOverrideUrlLoading(url)` | `false` cancels a navigation of a browser opened with `startBrowserWithShouldOverrideUrlLoading` | 30 s |
| `callbackjs(event, bookJson)` | section 5; `true` consumes the event | 120 s |
| an explore `action` | any JS text: `await eval(action)` in the page | 120 s |

Text sent to the debugger: `callHandler('text', type, html)` with type 0 search, 1 detail, 2 toc, 3 content, and
`callHandler('log', line)`.

## 4. JSON shapes

### 4.1 Book (search / find lists, info)
```json
{"bookUrl": "…", "name": "…", "author": "…", "kind": "状态,评分,标签,更新时间", "coverUrl": "…", "intro": "…",
 "tocUrl": "…", "wordCount": "12.5万", "type": 0, "latestChapterTitle": "…", "downloadUrls": ""}
```
`type`: 0 novel, 1 audio, 2 comic, 4 short drama. `wordCount` is reformatted to `n万字` (万/千 understood). `intro`
may be `@html:<html…>` (rendered; `$theme` becomes `dark` / `day`), `<useweb>` / `<usehtml>` forms, or plain text;
`@onclick:` buttons in it run their js in the page. `tocUrl` empty = use `bookUrl`.

### 4.2 Chapter
```json
{"name": "第一章", "chapterId": "…", "index": 0, "isPay": false, "isVip": false, "isVolume": false, "tag": ""}
```
`index` is overwritten with the position; `isVip` puts 🔒 before the name; `isVolume` rows are volume headers;
`chapterId` is what `content()` / `pay()` receive.

### 4.3 Discovery entries (`getfinds()`)
| `type` | meaning | fields |
|---|---|---|
| 0 (default) | with `url`: a list → `find(url, page)`; with only `js`: a button running it; neither: a full-width title | `title`, `url`, `js`, `width` |
| 1 | opens `url` in the app's web view | `title`, `url`, `width`, `useShouldOverrideUrlLoading` |
| 2 | drop-down: the choice is stored with `cache.set(title, value)`, then `action` runs; `default` shown first (or the last choice) | `title`, `chars`, `default`, `action`, `width` |
| 3 | input box, stored like a drop-down | `title`, `default`, `action`, `width` |
| 4 | button running `action` | `title`, `action`, `width` |

`width`: 0 auto, 1 half line, 2 two thirds, 3 full line. A list `url` may carry `##{"method":"POST","body":{…},
"header":{…}}` by convention (the page's `find` parses it; the app passes the text through).

### 4.4 Login form (`getloginurl()` answering JSON)
`[{"name": "账号", "type": "text", "default": ""}, {"name": "密码", "type": "password"},
  {"name": "线路", "type": "select", "chars": ["a", "b"], "default": "a"}, {"name": "注册", "type": "button", "action": "js"}]`
— the dialog saves `{"账号": "…", "密码": "…"}` as JSON with `cache.set('LoginInfo', …)` and calls `login()`.

### 4.5 Chapter text
Lines are paragraphs; the only HTML kept is `<img>` (`<p>`, `<br>` become line breaks, entities are decoded).
`<img src="URL,{json}">` options: `js` (run in the page when tapped), `headers`, `imageDecode`. `dp:N,{json}` is the
app's own 段评 bubble showing N. An image on the same line as text is drawn small (段评); `data:` images (svg too) work.
Audio books (type 1) and short dramas (type 4) return the media URL as the whole text.

## 5. Events (`callbackjs(event, bookJson)`)
With `eventListener` on, the detail page sends `clickBookName`, `longClickBookName`, `clickAuthor`, `longClickAuthor`,
`clickBookLabel`, `longClickBookLabel` (a `true` answer replaces the app's action: long presses otherwise search the
name / author), `addBookShelf`, `delBookShelf`, `saveRead` (fire and forget). With `customButton` on,
`clickCustomButton` / `longClickCustomButton` are sent whatever `eventListener` says.

## 6. Bridge handlers (`callHandler(name, …)`)

| name | arguments | answers |
|---|---|---|
| `CookieJar` | `isCookieJar` | — (marks the page ready) |
| `http` | `method` (`get`/`post`/`head`), `url`, `body`, `headersJson`, `followRedirects`, `contentType` | `{method, data, body (base64), headers {name: [v]}, statusCode, statusMessage}`; failures: `statusCode` 0, message in `statusMessage`. Stored cookies of the host are merged into `Cookie` (the page's own wins); a POST without content type sends `application/x-www-form-urlencoded`; `http2://` / `https2://` = HTTPS |
| `cache.get` / `cache.set` / `cache.remove` | `key` [, `value`] | this source's store (`null` when unset); `cache.allget/allset/allremove` is the store shared by all sources. Conventions: `LoginInfo` (login form), `<bookUrl>` (书籍变量), `<explore title>` (drop-down / input choice) |
| `cookie.get` / `cookie.set` / `cookie.remove` | `url` [, `"a=b; c=d"`] | the cookies of the url's host |
| `cookie.getCookie` / `cookie.setcookie` | `url`, `name` [, `value`] | one cookie (`null` when absent) |
| `webview` | `url`, `js`, `html`, `body`, `headerJson`, `overrideUrlRegex`, `urlregex` | background page: loads `html` under `url` (or `url`; POST when `body`), answers the first navigation matching `overrideUrlRegex`, the first loaded resource matching `urlregex`, else the value of `js` (page source when empty) once the page is quiet (60 s at most) |
| `webviewajax` | `url`, `html`, `body`, `headerJson`, `ajaxregex` | the response text of the first XMLHttpRequest whose url matches |
| `startBrowser` / `startBrowserWithShouldOverrideUrlLoading` | `url`, `title`, `headerJson` | front web view (captcha, manual login); answers the page html when closed; the second asks the page's `shouldOverrideUrlLoading(url)` before every navigation |
| `startBrowserDp` / `startBrowserDpWithShouldOverrideUrlLoading` / `startBrowserDpwithHtml` | `url`, `title` [, …] | half-height sheet (段评); `withHtml(url, html, title)` shows `html` under `url` |
| `openurl` | `url`, `mimeType` | opens an external app; `true` when it could |
| `log` / `text` / `showToast` / `showLongToast` | … | debugger line / debugger html (`type`, `html`) / toast |
| `refreshExplore` | — | reloads the discovery page (drops its cache) |
| `setHtml` | `html` | replaces the stored page of this source and restarts it (在线版地址更新) |
| `addbook` | `bookUrl` or book JSON | opens the detail page of that book in this source |
| `searchbook` | `key` | searches `key` with this source |
| `buildNumber` / `version` / `id` / `device` / `getWebViewUA` / `getLoginUser` | — | app build, version, device id, `ios` / `android` / `macos` / `windows` / `ohos`, UA, app account name |
| `toTraditional` / `toSimplified` / `utf8ToGbkUrlEncoded` / `base64encode` / `base64decode` / `htmlToText` | `text` | converted text |
| `getVerificationCode` | `imageUrl`, `headerJson` | what the user typed (`''` url = plain input) |
| `showvideoplay` / `voice` / `putLyric` / `refreshContent` / `getdurChapterIndex` / `getReadBook` / `getsvg` / `showsvg` / `addsvg` / `getsourceurl` / `getWidth` / `getHeight` / `getsearch` / `getDirectoryList` | … | player, TTS, lyrics, reader state, 段评 bubble chooser, misc (see `baswebview.dart`) |

## 7. Writing and testing a source

* Start from `sources/sdk/qyd-sdk.js` (the handler wrappers above as `FlutterJSBridge` / `Http` / `Cache` / `Cookie`,
  plus DOM / URL / model helpers under `QYD`) and `sources/langge/source.src.html` as a worked example; `node
  sources/build.mjs <name>` inlines the SDK and writes `dist/source.html` + `dist/source.json` (the import file).
* `sources/runner/run.mjs` runs a page on the desktop in headless Chrome with the handlers above implemented in Node
  (`search` / `info` / `chapter` / `content` / `finds` / `find` / `flow <key>` …), so a source can be debugged with
  the app's exact call semantics before it goes to the phone. `npm test` there runs the SDK + runner against a local
  fixture site.
* In the app: 书源管理 → 调试 (keyword, book url, `++tocUrl`, `--chapterUrl`) shows the page's `log` / `text` output.
