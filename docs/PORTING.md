# Porting rules (Phase 2) — read this before touching `app/lib`

Goal: the replica app does what 轻悦时光 2.2.1026 does and, as far as the decompiled code and strings tell, looks like it.
`app/` is the Flutter package `newread`; **file paths under `app/lib/` mirror `package:newread/...` of the original** (see
`analysis/skeleton/` for the per-file list of functions, `analysis/inventory/work_queue.tsv` and `owner2.tsv` for ownership of
anonymous functions).

## Sources of truth (local, read-only; absolute paths from the main checkout `F:\WorkSpace\Pycharm\RE-Lab\qread`)
| What | Where |
| --- | --- |
| Function-level code of the original | `analysis/dart/index.sqlite` + `tools/scripts/q.py` (`digest <addr>`, `show <addr>`, `str <regex>`, `callers`, `callees`, `file <path>`, `cls <regex>`); raw asm in `analysis/dart/blutter_v2/asm/` |
| Which functions belong to a file | `analysis/skeleton/<path>.dart`, `analysis/inventory/work_queue.tsv`, `owner2.tsv` |
| Models (fields, JSON keys) | `analysis/inventory/models_fields.tsv`; generated classes are already in `app/lib/models/` |
| Settings / prefs / file-store keys | `docs/SETTINGS.md`, `analysis/inventory/settings_keys.tsv` |
| Network contract of the own server | `docs/API.md`, `docs/MEMBERSHIP.md`; gRPC `docs/proto/` |
| UI strings per page | `docs/SCREENS.md` (CJK strings in pool order), `q.py str <regex>` |
| Book-source engine, rule syntax, JS bridge | `analysis/inventory/rule_engine.txt` |
| AI / TTS | `analysis/inventory/ai_tts.txt` |
| Assets of the original | `analysis/ipa_x/Payload/Runner.app/Frameworks/App.framework/flutter_assets/` (fonts, bg images, epub.js, monaco, shaders; copy what you need into `app/assets/` and declare it in pubspec) |

Run Python tools with `tools\venv\Scripts\python.exe -I` and `PYTHONUTF8=1`. The Bash tool collapses `\\` in heredocs: write
code containing backslashes with the Write/Edit tools. `q.py show` prints blutter pseudo-assembly: read the summary lines
(`r0 = LoadStaticField(..)`, string loads, calls, `Allocate…Stub -> Class`) rather than raw instructions.

## Fidelity rules
1. Keep original names: classes, file names, JSON keys, prefs keys, UI strings (copy Chinese text exactly from the pool strings).
2. Behaviour comes from the code: when a function matters, read its digest/show output and reproduce the control flow. Where the
   decompilation is unclear, implement the obvious behaviour and leave `// TODO(asm 0x1234): ...` with the address.
3. Never invent endpoints. Calls to qread.xyz-style services go through the own server (`Common.apiBase`, `UserApi`); third-party
   services (WebDAV, OpenAI-compatible APIs, TTS vendors) use the user's own configuration as in the original.
4. The app is for the owner's personal use: no analytics, no ads, no hard-coded third-party credentials. Do not copy the Edge TTS
   client-token constant or any key found in the binary.
5. Member-only features keep the original gate: `Vip.require()` (`lib/util/vip.dart`) reads `UserSession.isvip`; never bypass it.
6. Visual design: original screenshots are not available. Use Material 3, follow the original's layout hints from the widget
   strings/sizes you can read, keep everything responsive and dark-mode safe. The owner will correct looks from the CI screenshots.

## Engineering rules
* Work only inside the directories you own (the lead's brief lists them). Shared files (`lib/main.dart`, `lib/pages/main_page.dart`,
  `pubspec.lock`) belong to the lead: put an entry point in your own files (a `Widget` page class, a `Future<void> init()`), and say in
  your final report how to wire it.
* Dependencies: add what you need to `app/pubspec.yaml` (pure Dart or a mainstream iOS-capable plugin) and list them in the report.
* Plugins that need a device (audio, webview, file picker, tts) go behind a small interface so that unit tests run on the Windows host.
* Tests: `flutter test` must stay green and `flutter analyze` must report no issues. Each module needs real tests with fixtures
  (HTML/JSON/EPUB/TXT samples written under `app/test/fixtures/<module>/`). No test may touch the internet: use a local
  `HttpServer` on 127.0.0.1 where HTTP is needed.
* Commits: small, descriptive, English messages, end with the trailer line the lead gives you. Commit on your branch in your
  worktree; do not push, do not merge, do not touch other worktrees.
* Report format (final message, ≤ 700 words): what exists (paths), what is verified (tests), what is approximated or missing with asm
  addresses, dependencies added, how to wire the entry points.

## Navigation hooks
Areas never import another area's page files. Use `lib/common/nav.dart` (`Nav.openReader`, `Nav.openBook`, `Nav.openSearch`,
`Nav.openSourceEdit`, `Nav.openRss`, `Nav.openNamed(context, name)`); the lead wires them in `lib/main.dart` after merging. Route names
for `openNamed` are the original's file stems (`ai_model_page`, `tts_setting`, `theme_manager`, `webdav_page`, `source_page`,
`rss_page`, `history_page`, `txtrule_page`, `replace_page`, `highlight_page`, `read_setting_page`, `reading_statistics_page`, ...);
list the names your area handles in your report. Book-source engine calls go through the engine's public API (`util/webbook/`,
`api/sourceapi.dart`) once it is merged; until then put them behind a small interface in your own area.

## Ownership map
| Area | Directories under `app/lib/` |
| --- | --- |
| A data | `models/` (refine generated classes), `storage/`, `data/` (bookself, source, rss, replace, txtrule, highlight, notes, fonts, ground, svg, tts, webdav, exploration, chromemark, music), `common/`, `init/`, `dio/` |
| B engine | `util/legado/`, `util/webbook/`, `util/source/`, `util/regex/`, `util/html/`, `util/http.dart`, `util/cookie*.dart`, `util/json.dart`, `util/chinese_utils.dart`, `util/format.dart`, `api/sourceapi.dart`, `api/rssapi.dart` |
| C read core | `read/` (txt, epub, mobi, paging/layout, per-book rule storage `read/api/*`), `util/epub/`, `util/image/`, `util/cahce/` |
| D1 shelf pages | `pages/bookshelf_page.dart`, `pages/discovery_page*.dart`, `pages/book/`, `pages/search/`, `pages/history/`, `pages/exploration/`, `widget/` (except the reader widgets below) |
| D2 sources / RSS / web | `pages/source/`, `pages/rss/`, `pages/rss_page.dart`, `pages/web/` (keep `nwebview.dart` working), `pages/scanner/`, `pages/qread/`, `qread/` |
| F reader UI | `pages/read/`, `pages/txtrule/`, `pages/replace/`, `pages/highlight/`, `pages/image/`, `pages/video/`, `pages/setting/read_setting_page.dart`, `widget/read/`, `widget/pageflip/`, `widget/bookfx/`, `widget/slider/`, `widget/note_sheet.dart`, `widget/select_all_paragraph.dart`, `widget/delayed_selection_area.dart`, and the unfinished parts of `read/` |
| E extras | `pages/setting/`, `pages/theme/`, `theme/`, `ai/`, `pages/tts/`, `util/audio/`, `pages/webdav/`, `data/cloud/`, `pages/user/`, `pages/me_page.dart`, `pages/about_page.dart` |
