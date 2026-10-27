# Local storage of the original app

> See `SETTINGS.md` (second analysis pass, 268 keys) for the corrected storage layers and the full key inventory; where the two differ, `SETTINGS.md` wins.

Evidence: pool strings and the functions that load them (`q.py str`, `q.py digest`). Items marked **[open]** still need a
pass over the owning functions; the verified part is enough to design the replica's storage layer.

## Mechanisms
| Mechanism | Package | Use |
| --- | --- | --- |
| SharedPreferences | `shared_preferences` (static `Storage._prefs`, offset `0x3da0`) | session keys, sync state, small settings |
| JSON/file store | `storage/storage.dart` `Storage._read/_write` (isolate `compute` with `{path, value}`; writes through `tmp`/`tmp2` files, error text `写入文件失败`) | large lists (sources, books, rules) |
| GetStorage | `get_storage` | key-value containers **[open]** (container names not found in pool) |
| SQLite | `sqflite` via `flutter_cache_manager` only | table `cacheObject(_id, url, key, relativePath, eTag, validTill, touched, length)`, unique index `cacheObjectkey` (migrations add `key`, `length`) |
| Hive | `hive` (39 files in the snapshot) | `Hive.openBox` is not referenced by name in app code **[open]** |
| Plain files | `path_provider` | directories below |

The only `CREATE TABLE` in the snapshot is `cacheObject`; the app's own data is not in SQL.

## Directories under the app documents/support dir (created at start-up by `0x90bbe8`)
`/covers_cache /images /tab_icons /themes /item /epub /bookcache /bookcache2 /audio2 /books /bookrule /epubrule /bookmark
/chinese /audio /cache /covers /tts_analysis /backup`, plus `/fonts` (`Documents/fonts/`), `/background_music`, `/high`
(highlight rules), `/bookai`, `/book_reading_time`, `/reading_time`, `/local_tts`, `/backup_temp` + `/restore_temp`
(backup/restore staging, `main_page.dart` `0x10bac64`).
Backups are `.zip` files in `/Documents/backup/` on iOS (`pages/setting/backup_page.dart` `0x68fb40`).
Single files: `settings.json`, `tts.json`, `icon.txt` (+ `.tmp`, `.tmp2` while writing), `shareBookSource.json`.

## SharedPreferences keys recovered so far
* **Session / sync** (restored by `0x11284a8`): `isLoggedIn, username, tockenid, autoSyncEnabled, auto2SyncEnabled,
  autoSyncProgressEnabled, lastSyncTime, lastSyncTime2, lastSyncTimer3, cloudbookself, cloudsource, etag, grouptag,
  bjetag, rsstag, sourcetag, isvip, cloudtheme, cloudmark, groundmd5, svgmd5, markmd5, cloudtts, ttsmd5, email, nickname,
  avatar_url`.
* **Bound 轻阅读 backend**: `Qreadusername, Qreadpassword, Qreadurl, Qreadisbind`.
* **AI** (`storage/setting.dart`): `aiModelList, aiUrl, aiKey, aiModel, purifyUrl, purifyKey, purifyModel, purifyConcurrent,
  roleAnalysisUrl, roleAnalysisKey, roleAnalysisModel, ai_model_settings, ai_model_settings_v2`; legacy migration ids
  `legacy_default, legacy_role, legacy_purify, restored_*`; AI role library and chat sessions are stored as JSON
  (`AiCharacter`, `AiChatSession`).
* **Reader chrome**: `customHeaderLeft/Center/Right`, `customFooterLeft/Center/Right`, `topMenuButtons` (member-only to edit).
* Full inventory of the ~hundreds of reader/theme settings keys: **[open]** (they are spread over `pages/setting/*`,
  `pages/read/*`, `data/*`; `analysis/inventory/work_queue.tsv` lists the owning functions).

## Data files per feature (`data/*.dart`)
bookshelf `bookself.dart`, book sources `source.dart` / `qsource.dart`, RSS `rss.dart`, replace rules `replace.dart`, TXT TOC
rules `txtrule.dart`, highlight `highlight.dart`, notes `note_data_n.dart`, fonts `fonts.dart`, backgrounds `ground.dart`,
SVG icon sets `svg.dart`, TTS engines `tts.dart`, WebDAV servers `webdav.dart`, exploration templates `exploration.dart`,
chrome bookmarks `chromemark.dart`, background music `background_music_manager.dart`; models in `docs/MODELS.md`.
The cloud-sync item names (`getItemJson`/`setItemJsonFile`, field `item`) mirror these: `tts_engines`, theme, marks,
background, svg (`cloudtheme, cloudmark, groundmd5, svgmd5, markmd5, cloudtts, ttsmd5` are the matching sync switches/md5s).
