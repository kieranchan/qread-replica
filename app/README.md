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
| Reading core | `read/`, `util/epub/`, `util/image/`, `util/cahce/` | TXT (charset + TOC rules) / EPUB / MOBI import, layout + paging, per-book stores, progress, history, bookmarks, cache |
| Reader UI | `pages/read/`, `pages/{txtrule,replace,highlight,image,video}/`, `widget/{read,pageflip}/` | paging modes, menus, settings, selection → highlight / note, listening (system TTS), AI chat sheet, comic / audio views, rule pages |
| Shelf / search / discovery | `pages/bookshelf_page.dart`, `pages/discovery_page*.dart`, `pages/{book,search,history,exploration}/`, `widget/` | shelf (groups, grid/list, import, batch edit, cloud sync), detail, catalog, change source, downloads, multi-source search, discovery, 探索 templates |
| Sources / RSS / web | `pages/source/`, `pages/rss*`, `pages/web/`, `pages/scanner/`, `qread/` | source manager + editors + debugger (+ local debug server :5858), 订阅 tab, in-app browser, binding to the user's own 轻阅读 backend |
| Extras | `theme/`, `pages/{theme,setting,tts,webdav,fonts}/`, `ai/`, `util/audio/`, `data/cloud/`, `pages/me_page.dart` | themes + theme plaza, fonts, backgrounds, backup/restore (zip, WebDAV), AI models (OpenAI-compatible), HTTP TTS engines, WebDAV, statistics, Wi-Fi transfer (:5757) |
| Lead glue | `main.dart`, `init/wiring.dart`, `init/glue_routes.dart`, `init/reader_ai_adapter.dart`, `common/nav.dart`, `pages/main_page.dart` | `Nav` hooks and route tables between the areas, tabs, start-up |

Fidelity pass (2026-10-28): settings keys, prompts, defaults and flows re-read from the original; added page-curl effects,
header/footer slots, wakelock, screen brightness, PDF books, listening through every TTS engine (HTTP, Volcano, MiMo, web-view
pages, multi-role) with background music and lock-screen controls, AI purification and chat tools, in-app video, dictionaries,
highlight backgrounds, camera QR scanning, app links / open-with, Big5 + GB18030, per-source proxy, font de-obfuscation
(queryTTF/replaceFont), drag-sorted shelf, explore actions, 沉浸光感 (liquid glass), 底栏标签配置 (订阅 hidden by default as in the
original), backup devices on the owner's server, alternate home-screen icons.

Not available (pages keep the original strings and say so): 时光源 execution and the browser reading mode built on it (they need
qread.xyz services), Baidu/Weiyun drives (vendor credentials), the Edge voice (its client token is not copied), app update check.
The remaining approximations are marked `TODO(asm 0x…)` with what was checked.

## Tests
```powershell
. ..\env.ps1            # flutter on PATH, PUB_CACHE inside qread
flutter analyze; flutter test     # 524 tests, about 1.5 minutes
```
* Per area: `test/{data,storage,util,read,reader_ui,shelf,sources,extras}/`; the engine runs against a fake site on 127.0.0.1.
* `test/app_smoke_test.dart` starts the wired app and opens every tab; `test/route_coverage_test.dart` fails when a page opens a
  route name no table handles; `test/contract/server_contract_test.dart` drives `UserApi` against the real `../server`.
* `test/reader_ui/rule_pages_test.dart` has failed once in a full run and passed on rerun (timing-sensitive).

## UI test on the iOS Simulator (no phone needed)
`integration_test/app_flow_test.dart` + `test_driver/`, run by `.github/workflows/ios-ui-test.yml` against the real server started
on the macOS runner: privacy → signed out → login → gated switch → activation code → member → self-check → 会员中心, then books on
a demo site served inside the test (`integration_test/demo_site.dart`, text written for the test): import source → search →
detail → add to shelf → reader (page turn, menus) → shelf → 发现 / 探索 / 订阅. Screenshots of every step are the
`ui-screenshots` artifact (14 days).

## iOS
No Mac here: `.github/workflows/ios-unsigned.yml` builds `flutter build ios --release --no-codesign` on a macOS runner (Xcode 26.3)
and uploads `newread-unsigned.ipa`; install with Sideloadly. Repository: private `kieranchan/qread-replica` (root = `qread/`).
Windows desktop is not buildable locally and is not needed.
