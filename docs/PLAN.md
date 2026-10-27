# Replica plan — 轻悦时光 2.2.1026 (iOS)

Scope rules: replication is allowed and welcome. This plan, the analysis and
the replica may be copied, forked, modified, redistributed and re-created, in
whole or in part. The only prohibited use is malicious attack — attacking,
overloading or otherwise disrupting this project, any app, service or person.
Online features run on the owner's own server.

## Facts this plan rests on (from `analysis/README.md`)
- Flutter release build, Dart 3.12.2, not obfuscated. The app's own code is
  492 files in `package:newread/...`.
- 41 plugin frameworks are public pub/CocoaPods packages. The only app-specific
  binary is the Dart AOT snapshot (`App.framework/App`).
- All assets ship in the IPA: 14 backgrounds, 24 images, the Alimama
  boldface/circle fonts, Noto Sans SC, epub.js, domino.bundle.js, monaco and
  2 shaders.
- The backend is under `*.qread.xyz`: `/api/userapi`, `readapi`, `sourceapi`,
  `qsourceapi`, `rssapi`, `themeapi`, `ttsapi`, `uploadjson`, `book_*`, a TTS
  websocket, an MCP server and gRPC (`grcp/generated`).

## Phase 0 — recovery (second pass done 2026-10-27)
1. **Done.** blutter (patched for iOS Mach-O) dumps the whole snapshot to
   `analysis/dart/blutter_v2/`: named functions, 32.6k anonymous functions
   (`blutter_discarded`), and 3.97k code objects without a Function
   (`blutter_native`, where most of the account/cloud client lives) — 48,159
   functions, 98% of the instruction range. `newread` = 6,014 named + 4,942
   attributed anonymous functions. Details and the older dumps to delete:
   `analysis/README.md`.
2. **Done.** `tools/scripts/build_index.py` + `attribute_owner.py` +
   `q.py` give a queryable index (`analysis/dart/index.sqlite`);
   `make_skeleton.py` writes `analysis/skeleton/` (Dart skeletons, 442 files) and
   `analysis/inventory/work_queue.tsv` (every function with owner file, class,
   address, size). Instance field names are not in blutter's output; models take
   them from JSON keys (`docs/MODELS.md`).
3. Specs in `docs/` (generated ones say so in line 1):
   - `MEMBERSHIP.md`: how membership works and the owner's own design.
   - `API.md` + `API_FUNCTIONS.md`: the account/cloud API (49 calls), bound
     轻阅读 backend, other services. **Open:** the shipped base URL, request body
     encoding, the gRPC `.proto` files.
   - `STORAGE.md`: mechanisms, directories, session/AI keys. **Open:** the full
     settings-key inventory, GetStorage/Hive names.
   - `SCREENS.md` (119 page files with their UI strings), `MODELS.md`,
     `DEPENDENCIES.md` (133 packages; versions resolved at `pub get`),
     `IPA_INVENTORY.md` (Info.plist, entitlements, frameworks, assets).

## Phase 1 — app shell and iOS pipeline (first slice done 2026-10-27)
**Status:** `app/` exists (package `newread`, iOS 15, own bundle id); `UserApi`, `UserSession`, login / register / me / 会员中心 /
cloud-setting pages work against `server/` (18 tests, contract tests spawn the real server); `.github/workflows/ios-unsigned.yml`
and a root `.gitignore` are ready but no git repository exists yet — **the private GitHub repo needs the owner's go-ahead.**

- `app/` is a Flutter 3.44.9 project with package name `newread`, so file
  paths match the original 1:1. It uses its own bundle id and the same
  dependency versions. A script copies the assets in from `analysis/ipa_x`.
- GitHub Actions on a macOS runner runs `flutter build ios --release --no-codesign`,
  packs `Payload/` into an unsigned IPA artifact, and the owner installs it
  with Sideloadly. This needs a **private** repo under `kieranchan`. Ask the
  owner before creating it and pushing (code and assets go to GitHub).
- Local loop on Windows: `flutter test` (unit and widget goldens) and
  `flutter analyze`. A Windows desktop build serves only as a smoke run.
  iOS-only plugins are stubbed there.

## Phase 2 — port, dependency-first
`models/` → `storage/`, `data/` → `util/` (regex, legado and webbook
`analyze_rule`, html, epub, image, cache) → `read/` (txt, epub, mobi
parsing and paging) → `widget/` → `pages/` (bookshelf, search, book detail,
reader, sources, rss, settings, themes, tts, webdav, user) → extras (`ai/`,
`desktop_lyric`, video, scanner).
Every file is rebuilt from its blutter asm. The rebuild must preserve names,
literals, control flow and widget-tree shape. The one intentional content
change is the in-app agreement (`pages/setting/user_ys.dart`): the replica uses
the replica policy above — copying, forking and re-creation allowed and welcome,
malicious attack prohibited — instead of the original text.

## Phase 3 — own server
Implement the `/api/*` and gRPC calls the app really uses on the owner's
Azure VM (see the dgtf2 server notes for deploy and rollback). Scope it after
Phase 2 shows which calls matter. The account and membership system is the
owner's own (`MEMBERSHIP.md` §4–5): the same wire contract as `API.md`, vip state
and activation codes held on the owner's server; the original service's
membership, purchase and auth are not touched. Build order: accounts and tokens,
membership + codes + `/vip` page, then cloud sync. **Status 2026-10-27:** all
three are built and deployed (`server/`, `https://qread.forfine.me`, shared Korean VM
with the td2 game server); remaining: backup-upload endpoints, optional mail, the
compatibility-engine allocator, and verification against the replica app.

## Verification (the owner does not test by hand)
- Function coverage metric: build the replica for iOS in CI, run the same
  patched blutter on its `App`, and diff function lists and code sizes per
  file against the original. The target is every original function present
  with a size within tolerance.
- Unit tests: the Legado rule engine (CSS, XPath, JSONPath, regex and JS
  rules) on fixtures, txt/epub paging, and the storage schema.
- Widget golden tests for every page with fixture data.
- Optional, owner's choice: a one-time set of reference screenshots of the
  original app from the owner's iPhone, for visual diffs.
