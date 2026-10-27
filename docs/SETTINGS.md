# Settings and key/value storage of 轻悦时光 2.2.1026

Generated inventory: `analysis/inventory/settings_keys.tsv` (268 rows; script `tools/scripts/inventory_settings.py`, meanings
hand-written in `tools/scripts/settings_meanings.tsv`). Tags: **[code]** read from decompiled functions, **[infer]** deduced.

## 1. Storage layers (correcting `docs/STORAGE.md`)
| Layer | Access path | Keys | Notes |
| --- | --- | --- | --- |
| **prefs** = `SharedPreferences` | `Storage.getString(key)` `0xd53c0` (= `prefs.get(key)?.toString() ?? ""`, 189 call sites) / `Storage.setString` `0xe65a8c` (173 call sites, `Future<bool>`) [code] | 187 literal + 6 templates | **Every value is a String.** Typing is done by the caller: `toBool` `0xd52bc` (null->false, `"true"`/`1`->true), `toInt` `0x1cac00`, `double.tryParse` `0x368a0`/`0x1b97b0`, `int.parse` `0x418d4`, `int.tryParse` `0x1fce8`. Setters store `"true"`/`"false"`/decimal text. |
| **file store** ("item" files) | `Storage.read(key)` `0xe66a0c` (87 call sites) / `Storage.write(key, value)` `0xe06f14` (101) [code] | 55 literal + 16 templates | One text file per key: `<documents>/<dir>/<md5hex(utf8(key))>.txt`; written through `…tmp` / `…tmp2` files (isolate `compute` of `Storage._write`, error text `保存失败: …, 错误: …`; reads `读取失败`/`不存在`). `<dir>` is static `0x1ed4`, never stored by code: **[open]**, most likely `item` [infer: backups require an `item/` directory, `备份文件错误：缺少必要的settings.json或item目录`]. Holds session/sync state and the big JSON lists (`bookself`, `source`, `rss2`, `replaces`, …). Values are Strings (JSON text for lists). |
| `icon.txt` | read `0x10d0708`, write `0x1054d74` [code] | 1 | `<documents>/icon.txt` (alternate app icon name) via the same tmp/tmp2 writer. |
| plain JSON files | `Storage._read/_write` with `{path,tmp,tmp2}` | `settings.json` (backup), `tts.json`, … | see `docs/STORAGE.md` for the file list |
| GetStorage / Hive | present as library code only; **no app call sites found** (`get_storage` has 0 external callers, Hive pool strings belong to the library) | – | The earlier "GetStorage [open]" can be dropped. |

* The file-store **key is hashed**, the prefs key is not. `Common.cleanwhite` (static `Set<String>` 0x3cc8) holds the md5 hexes of the
  27 account/sync keys that must survive a "clean" (it is filled at the top of `0x11284a8`, which then loads the session
  statics): `isLoggedIn username tockenid autoSyncEnabled auto2SyncEnabled autoSyncProgressEnabled lastSyncTime lastSyncTime2
  lastSyncTimer3 cloudbookself cloudsource etag grouptag bjetag rsstag sourcetag isvip cloudtheme cloudmark groundmd5 svgmd5
  markmd5 cloudtts ttsmd5 email nickname avatar_url` [code]. So `0x11284a8` is "build the keep-list + restore session from the file
  store", not a prefs restore as `docs/API.md` §Session states. The per-key getters it calls (`0x1129260 … 0x11295f8`) are
  `static Future<bool|String> getX()` = `toBool(await Storage.read("x"))` etc.
* Bound-backend keys carry the device id: `Qreadisbind<appid>`, `Qreadurl<appid>`, `Qreadusername<appid>`,
  `Qreadpassword<appid>`, `accessToken<appid>`, `baseurls<appid>`, `qreadcaneditsource<appid>` (key = literal + static `0x1e60`
  `appid`) [code]. (`docs/STORAGE.md` lists them without the suffix.)
* Per-item key families (templates; `{}` = a book url / source url / id built at run time): `{sourceUrl}ExploreUrl`,
  `QExploreUrl{…}`, `{bookUrl},page` (layout/paging cache), `book_chapter:{…},…` (chapter/purify cache), `video_progress_{id}`,
  `{…}rsshistory`, `rsstype{…}`, `skipStartTime{…}`/`skipEndTime{…}` and `ttsEngine{…}` (per-book, prefs), `{…}default`.
  65 further call sites build their key from several variables (big UI functions); they are not listed (see the `<unresolved>` row).

## 2. Backup / restore of settings [code]
Backup (`pages/setting/backup_page.dart`, isolate `_performBackupInIsolate`) writes a `.zip` into `<documents>/backup/` (name
`<backupName>_<yyyyMMdd…>.zip`) that contains `settings.json` (the `settings` map = a dump of the SharedPreferences key/value pairs,
read with `prefs.get(key)` in a loop, auto-backup `0x10bb7d0`) and the data directories `/bookcache2 /bookrule /bookmark /bookai
/book_reading_time /books /cache /audio2 /covers /covers_cache /fonts /epub /images /item /high /reading_time /tab_icons /themes
/background_music`. Restore requires `settings.json` and the `item/` directory. AI model settings are restored from the backup
keys `ai_model_settings_v2` (JSON `{version, models[AiModelConfig…]}`) or legacy `ai_model_settings` (`roleAnalysisUrl/Key/Model`,
`purifyUrl/Key/Model`, `purifyConcurrent`; migrated to ids `restored_default/restored_role/restored_purify`) (`0x1090800`).

## 3. Where to read the rest
* `settings_keys.tsv` columns: `key, key_kind (literal|template|dynamic), store (prefs|file|icon), rw, type (bool|int|double|string|json?|?),
  default, literal_set_values, getter_fns, setter_fns, n_getter_callers, n_setter_callers, owner_file, caller_files, ui_hint, confidence, meaning`.
  `type` comes from the thin accessor (one helper call, size <= 0x100); `?` = only non-thin readers (big functions) were found;
  `json?` = file-store key owned by `data/*`, `read/*` or `qread/*` [infer]. `default` is the literal loaded after the read in the
  accessor (strings) or the number after it (`6` etc. may be the clamp bound rather than the default: [infer]).
* `owner_file` = file the accessor was attributed to (`owner` table; most accessors are anonymous; with `owner2` 86 of 268 stay `?`, 166 with the original `owner` table;
  `caller_files` gives the files that call the accessor).
* Open: the file-store directory name (static `0x1ed4`), the exact value domains of enum-like ints (`dark`, `turntype`, `userAgentType`,
  `bottomBarType`, …) and which keys are written by the reader pages vs only restored from backups.

## 4. Corrections to `docs/API.md` found while tracing the session keys [code]
* **`Userinfo` slot order** (dataflow through the constructor spill slots in both `getUserInfo` `0xf65400` and `login` `0x107c250`; full table in
  `analysis/inventory/models_fields.tsv`): slot0 `username`, slot1 (`0xf`) **`vip`**, slot2 (`0x17`) **`id`**, slot3 `email`, slot4 `nickname`, slot5 `avatar_url`,
  slot6 `isvip`. The apply function `0xf64ebc` stores slot2 into the session-token static `0x1f20` (`tockenid`, the value sent in every later request and persisted
  under the file-store key `tockenid` by `0xf652ec`) and slot1 into static `0x1f90`. Hence **the token is the JSON key `id`, not `vip`**; `vip` is a *display string*
  for the member card (`pages/me_page.dart` `0x51dac0`: `0x1f90.contains("永久")` hides the 「立即开通」 button, otherwise the text is shown; also read in
  `user_setting_page.dart`). `docs/API.md` / `docs/MEMBERSHIP.md` assumed `vip` = token from the key *order*.
* Session restore `0x11284a8` first builds `Common.cleanwhite` (md5 of 27 keys, see §1) and then loads the statics from the file store.
* The original `owner` table's rule `caller` (2,773 newread functions) has only ~80% precision on a clean hold-out (see `tools/scripts/attribute_owner2.py --eval`);
  `analysis/inventory/owner2.tsv` carries a confidence column.
