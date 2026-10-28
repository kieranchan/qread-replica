# newread — the replica app (Flutter 3.44.9 / Dart 3.12.2)

Package name `newread`, like the original, so `lib/` paths mirror `package:newread/...` of the decompiled app
(`analysis/skeleton/`). Bundle id `com.kieranchan.qreadreplica.newread`, display name 轻悦复刻, iOS 15+.
Account / membership / cloud calls go to the owner's server (`../server`, live at `https://qread.forfine.me/`; override with
`--dart-define=QREAD_BASE_URL=http://127.0.0.1:8920/`). Porting rules and the area map: `../docs/PORTING.md`.

## What is in the app (status 2026-10-28)
Five tabs in the original's default order (`bottomBarTabs`): 书架 · 发现 · 探索 · 订阅 · 我的, first-launch privacy dialog,
"继续阅读" prompt, theme-driven tab bar.

| Area | Where | What |
| --- | --- | --- |
| Account + membership | `api/userapi.dart`, `data/user.dart`, `pages/{login,register,forgot_password}_page.dart`, `pages/user/`, `util/vip.dart` | login/register (invite code), 会员中心 web view, member gates (`Vip.require()`), cloud switches, devices, self-check |
| Data layer | `storage/`, `data/`, `common/`, `init/appinit.dart`, `models/` | prefs as text + file store `<root>/item/<md5>.txt`, every list manager, three-way cloud sync |
| Book-source engine | `util/webbook/`, `util/legado/`, `util/html/`, `util/http.dart`, `api/sourceapi.dart`, `api/rssapi.dart` | Legado rules (CSS/jsoup, XPath, JSONPath, regex, JS via JavaScriptCore on iOS / Dart interpreter on the host), search, explore, info, toc, content, RSS, debugger |
| 时光源 runtime | `util/source/`, `pages/web/source_webview.dart`, `pages/source/sg_login.dart` | the original's own sources: the source's `html` page runs in a HeadlessInAppWebView per source (reused, dropped after 5 idle minutes), the page's `callHandler` bridge (http, cache, cookie, webview, browser, captcha, …), search / 发现 / info / toc / content / pay / imagedecrypt through `SourceApi`, login (`getloginurl()` page or form + `login()`) |
| Reading core | `read/`, `util/epub/`, `util/image/`, `util/cahce/` | TXT (charset + TOC rules) / EPUB / MOBI + AZW3 (PalmDOC, Huffman/CDIC, KF8) import, layout + paging, per-book stores, progress, history, bookmarks, cache |
| Reader UI | `pages/read/`, `pages/{txtrule,replace,highlight,image,video}/`, `widget/{read,pageflip}/` | paging modes, menus, settings, selection → highlight / note, listening (system TTS), AI chat sheet, comic / audio views, rule pages |
| Shelf / search / discovery | `pages/bookshelf_page.dart`, `pages/discovery_page*.dart`, `pages/{book,search,history,exploration}/`, `widget/` | shelf (groups, grid/list, import, batch edit, cloud sync), detail, catalog, change source, downloads, multi-source search, discovery, 探索 templates |
| Sources / RSS / web | `pages/source/`, `pages/rss*`, `pages/web/`, `pages/scanner/`, `qread/` | source manager + editors + debugger (+ local debug server :5858), 订阅 tab, in-app browser, binding to the user's own 轻阅读 backend |
| Extras | `theme/`, `pages/{theme,setting,tts,webdav,fonts}/`, `ai/`, `util/audio/`, `data/cloud/`, `pages/me_page.dart` | themes + theme plaza, fonts, backgrounds, backup/restore (zip, WebDAV), AI models (OpenAI-compatible), HTTP TTS engines, WebDAV, statistics, Wi-Fi transfer (:5757) |
| Lead glue | `main.dart`, `init/wiring.dart`, `init/glue_routes.dart`, `init/reader_ai_adapter.dart`, `common/nav.dart`, `pages/main_page.dart` | `Nav` hooks and route tables between the areas, tabs, start-up |

Fidelity pass (2026-10-28): settings keys, prompts, defaults and flows re-read from the original; added page-curl effects,
header/footer slots, wakelock, screen brightness, PDF books, offline read-aloud (sherpa-onnx models imported or downloaded through
the owner's `static/down.json`), listening through every TTS engine (HTTP, Volcano, MiMo, web-view
pages, multi-role) with background music and lock-screen controls, AI purification and chat tools, in-app video, dictionaries,
highlight backgrounds, camera QR scanning, app links / open-with, Big5 + GB18030, per-source proxy, font de-obfuscation
(queryTTF/replaceFont), drag-sorted shelf, explore actions, 沉浸光感 (liquid glass), 底栏标签配置 (订阅 hidden by default as in the
original), backup devices on the owner's server, alternate home-screen icons.

Detail pass (2026-10-28, on the owner's phone): 时光源 search / discovery filters (`filter()` / `findfilter(url)`), 事件监听
(`callbackjs` for detail taps, shelf add/remove, saved progress), 定制按钮 (detail app bar + reader top bar), `@onclick` intro
buttons, 段评 bubbles (`dp:N`, tap → `showCmt` sheet) and `showsvg`/`getsvg`/`addsvg`, background web views as the original
`_Webview` (webviewajax, timers, `getheader` cookies, `setHtml`); change-source tabs 匹配书籍 · 不同作者 · 相近名称; highlight
rules with font size / line height measured in paging; 谷歌汉字 font; the original's TXT rule choice; 轻阅读 backend device jobs and
导入后端; TOC cache under `book_chapter:<url>,<type>`; browsers import links to `.json` source files.

时光源 pages encrypted with `@aes` are decrypted as in the original (0xe8a4c0) when the build gets the key with
`--dart-define=QREAD_SOURCE_AES_KEY=…` (CI: the repository secret of the same name; the key is not in the repository).

Browser 阅读模式 (2026-10-29): the in-app browser's menu turns the open page into a book as the original does (0xfcec20: the page's
html goes to the 「浏览器」 时光源's `getinfo(html, url)`, then the detail page). The original fetches that source's page from
qread.xyz; the replica has its own (`util/source/browser_source_page.dart`, plain DOM: meta tags / text for the detail, the
links sharing the most common directory for the catalog, the biggest text block for a chapter, 下一页 followed on both), handed out
by `Sourcedata.byUrl` for every origin ending in `@chrome` (`util/source/browser_source.dart`). The owner's server may serve a
newer copy at `static/browser.html` (`node tools/browser_page.mjs` in `../server`, then `qread-admin set-static browser`); the
app fetches it at start-up and prefers it, so the parser can change without a new build. Checked against a real 笔趣阁 catalog
page in a browser harness (171 chapters, clean text); `node --test test/js/browser_source_test.mjs` covers the pure helpers.

Not available (pages keep the original strings and say so): Baidu/Weiyun drives (vendor credentials), the Edge voice (its client
token is not copied). The update check (关于 page and main-page start-up) asks the owner's server, which
answers from `qread-admin set-update`.
The remaining approximations are marked `TODO(asm 0x…)` with what was checked.

## Tests
```powershell
. ..\env.ps1            # flutter on PATH, PUB_CACHE inside qread
flutter analyze; flutter test     # about 625 tests, about 2 minutes
```
* Per area: `test/{data,storage,util,read,reader_ui,shelf,sources,extras}/`; the engine runs against a fake site on 127.0.0.1.
* `test/app_smoke_test.dart` starts the wired app and opens every tab; `test/route_coverage_test.dart` fails when a page opens a
  route name no table handles; `test/contract/server_contract_test.dart` drives `UserApi` against the real `../server`.
* `test/reader_ui/rule_pages_test.dart` and `test/shelf/detail_catalog_test.dart` have each failed once in a full run and passed
  on rerun (timing-sensitive).

## UI test on the iOS Simulator (no phone needed)
`integration_test/app_flow_test.dart` + `test_driver/`, run by `.github/workflows/ios-ui-test.yml` against the real server started
on the macOS runner: privacy → signed out → login → gated switch → activation code → member → self-check → 会员中心, then books on
a demo site served inside the test (`integration_test/demo_site.dart`, text written for the test): import source → search →
detail → add to shelf → reader (page turn, menus) → shelf → 发现 / 探索 / 订阅. Screenshots of every step are the
`ui-screenshots` artifact (14 days).

## Testing on the owner's iPhone (USB, remote taps)
`phone/phone.py` (repository root; usage in its header) drives the sideloaded replica from this PC: screenshots, the visible texts
and buttons with their positions, taps, long presses, drags, typing, back. iOS accessibility presses do not reach Flutter buttons,
so the taps go through the app's QA driver `lib/dev/qa_driver.dart`: it is off unless `phone.py qa-on` puts the file
`<documents>/.qa_driver` into the app container over USB (the file holds a token every request must carry; the server listens on
127.0.0.1:8765 only, reached through usbmux). `phone.py qa-off` removes the file again; do that when the check is done.
```bash
tools/idevice-venv/Scripts/pymobiledevice3 mounter auto-mount     # once per phone boot, for screenshots
MSYS_NO_PATHCONV=1 tools/idevice-venv/Scripts/python phone/phone.py qa-on
MSYS_NO_PATHCONV=1 tools/idevice-venv/Scripts/python phone/phone.py texts
MSYS_NO_PATHCONV=1 tools/idevice-venv/Scripts/python phone/phone.py tapt 发现
MSYS_NO_PATHCONV=1 tools/idevice-venv/Scripts/python phone/phone.py shot shot.png
MSYS_NO_PATHCONV=1 tools/idevice-venv/Scripts/python phone/phone.py qa-off
```
Ask the owner before driving the phone, and only take screenshots while the replica is in front. Files of the app container can
be read with `pymobiledevice3 apps pull <bundle> /Documents/item/<md5 of the store key>.txt <local file>` (settings, sources).

## iOS
No Mac here: `.github/workflows/ios-unsigned.yml` builds `flutter build ios --release --no-codesign` on a macOS runner (Xcode 26.3)
and uploads `newread-unsigned.ipa`; install with Sideloadly. Repository: private `kieranchan/qread-replica` (root = `qread/`).
Windows desktop is not buildable locally and is not needed.
