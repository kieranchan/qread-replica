# API surface of 轻悦时光 2.2.1026

Recovered from the AOT snapshot (`analysis/dart/index.sqlite`; function addresses are the ones `q.py show <addr>` prints).
Confidence tags: **[code]** read from the decompiled function; **[infer]** deduced from slot order / naming / defaults;
**[open]** not recoverable from code. The wire is plain HTTP(S) to a base URL held in a static field, so the replica's
only server-side dependency is the contract below.

## 1. Account and cloud API (`UserApi`, ~50 request functions)

### Transport [code]
* URL = `<base>` + endpoint name, `<base>` = static field `0x1da0` (offset `0x3b40`). No code ever writes this field
  (its value is set when the snapshot is built), so the shipped host is **[open]**; the 会员中心 page uses the same base
  (`<base>vip?tockenid=<token>`). The replica makes it configurable and points it at the owner's server.
* Every call is a **POST** built by the shared helper `0xe0e910` as `{url, body}` + method `"post"` and run through the app
  HTTP worker `0xf1f6b4` (Dio, isolate, cookie jar, optional `header`, `move` = follow redirects, `timeout`). The reply bytes are decoded by `_decodeBytes` (UTF-8 + JSON).
* Body = a map. Common keys: **`tockenid`** (session token, static `0x1f20`), **`appid`** (device id read at start-up,
  static `0x1e60`), **`t`** (current time in ms: `_getCurrentMicros() / 1000`). Dio sends a map as JSON by default
  **[infer]**; the own server accepts JSON and form bodies.
* Reply = JSON `{code, data?, errorMsg?}`. `code` is converted to int by `0x1cac00` and a non-zero value takes the failure
  branch, so `0` = success **[infer]**. Failures carry `errorMsg` (`imgupload` uses `message`). Cloud getters return the
  payload as a JSON **string** in `data` and parse it client-side.
* Multipart calls (`file` field, Dio `FormData`): `updateAvatar`, `imgupload`, `setItemJsonFile`; the token (and for
  `setItemJsonFile` also `appid`, `item`, `t`) travel in the query string.

### Account (no token)
| Endpoint | Request | Reply `data` | Where |
| --- | --- | --- | --- |
| `login` | `username` (name or email), `password`, `platform` (`ios` on iOS **[infer]**), `model`, `appid` | `{username, id, vip, isvip, avatar_url, nickname, email}` | `0x107c250` |
| `register` | `username`, `email`, `password`, `code` (6-digit email code) | – | `0x108fcb8` |
| `getEmailCode` | `email` | – | `0x10901a0` |
| `forgetPassword` | `email` | – | `0x107bdac` |

`Userinfo` (size `0x40`, 7 slots; applied by `0xf64ebc`) — **slot order verified** in the constructors of `login` (`0x107c250`) and
`getUserInfo` (`0xf65400`), whose spill slots feed the stores: slot0 `username`, slot1 **`vip`** (a String → static `0x1f90`, display
text: `me_page` hides 立即开通 when it contains `永久`), slot2 **`id` → the session token** (static `0x1f20` = `tockenid`, sent with every
request and persisted by `0xf652ec`), slot3 `email` (`0x1f24`), slot4 `nickname` (falls back to `username` when empty, `0x1f28`),
slot5 `avatar_url` (`0x1f2c`), slot6 `isvip` (→ static `0x1f30`). JSON keys parsed: `username, id, vip, isvip, avatar_url, nickname, email`.
So **the token is `data.id`**, not a separate key and not `vip`. (An earlier version of this file inferred `vip` = token from the parse
order; the analysis sub-agent corrected it and the spill-slot trace above confirms it.) The own server returns `id` = token and `vip` =
`""` / a date / `永久`, plus extra keys the app ignores (`userId`, `vipUntil`).

### Account (with `tockenid`)
| Endpoint | Extra request keys | Reply | Where |
| --- | --- | --- | --- |
| `getUserInfo` | `appid`, `t` | `data` = same map as login | `0xf65400` |
| `logout` | `t` | – | `0x10489fc` |
| `cleanuser` | `t` | – (delete account data) | `0x1048bb4` |
| `updateNickname` | `nickname`, `t` | – | `0x1049b6c` |
| `updateAvatar?tockenid=` | multipart `file` | `data.avatar_url` | `0x10494c0` |
| `imgupload?md5=&tockenid=` | multipart `file` | `{code, message}` | `0xfca7f8` |
| `hasimg` | `appid`, `md5`, `t` | – (code tells whether the image exists) | `0xfcabc8` |
| `changePassword` | `oldpassword`, `newpassword` | – | `0x10acfe8` |
| `getloginDevice` | `t` | `data` = devices (`models/logindevice.dart`) | `0x1048ef8` |
| `removeDevice` | `appid`, `t` | – | `0x10ad4bc` |
| `getAutoDevice`, `getAuto2Device` | `t` | `data` = backup devices (`models/autodevice.dart`: `model, platform, appid`) | `0x1051ddc`, `0x1052068` |
| `removeAutoDevice` | `appid`, `t` | – | `0x10518a4` |
| `canOpenCloud` | `t` | `code` only (+`errorMsg`): server-side cloud permission | `0xfcb7e4` |
| `paynew` | `vipType`, `paymentType` | `data` = `"ok"`; Windows build answers `暂不支持` | `0x10b8894` |

### Cloud sync (all need `tockenid`; `appid`/`t` where listed)
Five data kinds share one pattern: an **etag** getter, an **update-url** getter that takes the client's etag and answers
`-1` when unchanged (otherwise a download location), and a **list** getter. Last-seen etags live in prefs
(`etag`, `grouptag`, `bjetag`, `rsstag`, `sourcetag`).

| Kind | Etag | Update url (`etag`, `t`) | List |
| --- | --- | --- | --- |
| Bookshelf | `getEtag` `0xe672ec` | `getBookUpdateurl?st=1` `0xe682a8` | `getBooks?st=1` `0xe67d68` (`bookUrl` per item) |
| RSS sources | `getBRssEtag` `0xe72e94` | `getBRssUpdateurl?st=1` `0xe73a20` | `getBRss?st=1` `0xe73670` |
| Book sources | `getBSourceEtag` `0xe76e5c` | `getBSourceUpdateurl?st=1` `0xe77818` | `getBSource?st=1` `0xe77468` |
| Notes | `getBjEtag` `0xed415c` | `getBjUpdateurl` `0xed4ea8` | `getBjs` `0xed4a40` |
| Groups | `getGroupEtag` `0xf19fd0` | `getGroupUpdateurl` `0xfcd6cc` | `getGroups` `0xf199ac` (adds the 「全部」 group) |

Other cloud calls: `getItemJson` (`appid`, `item`, `t`; items include `tts_engines`, theme, marks, backgrounds, svg) and
`setItemJsonFile?tockenid=&appid=&item=&t=` (multipart `file`) at `0xe6f7b8`/`0xe6ef90` and the twin pair
`0xea5fd4`/`0xea5a98`; reading progress `addreads` (`appid`, `book`, `readchapter`) `0xecc0d0` and `autopos` (`st`, `appid`,
`book`, `index`, `pos`, `bid`) `0xecd518`. Device backups (`openAuto`, `newopenAuto2`, `getBookSelf`, `getSources`, `getRss`): see
"Device backups" below.
The generated table of all 49 functions with the pool strings in code order is `docs/API_FUNCTIONS.md`.

### More calls found in the second pass [code]
`getItemMd5` (`appid`, `item`, `t` → `data` = md5 of the stored item; the app compares it with its local md5, message `一样不必同步`),
`getAuto2Device` / `removeAuto2Device` / `newopenAuto2` (`st`, `appid`; `data` = `{source, rss}`), `check_update` (see below), `upload` (multipart image → `{code, url, message}`), `svgtopng`.
Item names seen with `getItemJson`/`setItemJsonFile`: `tts_engines`, `exploration_templates_backup`, `ai_model_settings_v2`, `readitems`,
`readtheme`, `svg`, `markname`.

### Device backups (书架备份 / 书源备份) [code]
Automatic backups of one device, separate from the cloud lists above. The server hands out **upload / download urls**; the app
moves the data itself with the HTTP worker's `putCos` (Dio `PUT url` with the JSON text as body, `0xe13cdc`; 413 →
`当前请求内容过多，超出服务器限制`, 403 → `当前请求被拦截，请联系管理员关闭防火墙`) and `get` (`0xe68198`, bytes; errors `网络错误:  <e>`).

| Endpoint | Request | Reply `data` | Where |
| --- | --- | --- | --- |
| `openAuto` | `tockenid`, `appid` (this device), `st` (`"0"` = the user switches 书架备份 on, `"1"` = start-up re-open `0xf22200`), `t` | upload url of this device's bookshelf backup (String → static `0x1f4c`); failure: `autoSyncEnabled` off + `errorMsg` thrown | `0xf223ac` |
| `newopenAuto2` | same | `{source, rss}` upload urls (statics `0x1f50` / `0x1f54`); failure: `auto2SyncEnabled` off | `0xf226c4` |
| `getAutoDevice` / `getAuto2Device` | `tockenid`, `t` | `[{model, platform, appid}]` backup devices | `0x1051ddc` / `0x1052068` |
| `removeAutoDevice` / `removeAuto2Device` | `tockenid`, `appid`, `t` | – | `0x10518a4` |
| `getBookSelf` | `tockenid`, `appid` (**the backup device**), `t` | download url; the app GETs it and parses a `Book` list (`code != 0` → empty list, errors → `获取书架书籍失败:`) | `0xfa8894` |
| `getSources` / `getRss` | `tockenid`, `appid` (backup device), `t` | download url; the device dialog GETs it and imports (a message with `404` → `此设备书源备份为空` / `此设备订阅源备份为空`) | `0x105127c` / `0x1050ff4` |

Uploads: bookshelf `0xe65010` (all shelf books as JSON, then prefs `lastSyncTime` = `yyyy-MM-dd HH:mm:ss`), sources `0xe7665c`
(`lastSyncTime2`), RSS `0xe72958` (`lastSyncTimer3`); after a save a 10 s timer uploads when the switch is on and the url known
(`0x1bc564`, `0x1c7e34`, `0x1c5610`). The 备份导入 entry of the shelf opens the device dialog (`AutoDeviceManagementDialog`, bool
`false` = bookshelf devices, `true` = source devices); a bookshelf device opens `BackbookPage(appid)`. The own server serves the
urls as `<base>/autobackup/<32 hex>` (`PUT` stores, `GET` reads, 404 until the first upload); st `"1"` fails when the device is
no longer registered, which turns the switch off on that device (as the original does on any failure).

### Result codes and the sync flow [code unless marked]
* `code == 0` success, `code == -5` "nothing stored" (the getters then return `""`), any other code is a failure: the cloud-sync flags
  `0x1f94/0x1f98` are switched off, a toast shows `errorMsg`, and the update-url getters return `"-1"`.
* Bookshelf sync (`0xe6766c`): `result = get<Kind>Updateurl(etag = last known etag)`; on the merge branch it fetches the list
  (`getBooks?st=1`, a JSON string of a book list keyed by `bookUrl`), merges by `phone_book`/timestamps and uploads. Read with the Dart bool encoding (`true` = NULL+0x20, so `tbz w0,#4` jumps on `true`), the merge branch is taken when the
  result is `""` or `"-1"`; any other value skips it and is stored in static `0x1f4c`. So the server answers **the etag (non-empty) when
  the client is current and `""` when newer data exists** (`-5` = nothing stored also yields `""`). Verified twice (data agent and lead).
* Error text for an expired token is `NEED_LOGIN` (`0xe1f6c` maps it to `登陆已过期`) **[infer]**.

### Session state [code]
Restore from prefs: `0x11284a8` (keys `isLoggedIn, username, tockenid, autoSyncEnabled, …, isvip, email, nickname, avatar_url`);
apply a `Userinfo`: `0xf64ebc` (sets statics `0x1f18` logged-in, `0x1f1c` username, `0x1f20` token, `0x1f90` id, `0x1f30` isvip,
`0x1f24/0x1f28/0x1f2c`; calls the callback in static `0x1f68`; then, **for each of the three cloud-sync flags
`0x1f9c/0x1fa0/0x1fa4`, `if (!isvip && flag) { flag = false; persist }`**); logout:
`0x10487c4` (token → `""`, flags false).

## 2. Bound 轻阅读 backend (user-supplied server, not qread.xyz) [code]
`Qread.baseurls` (list, static `0x3a98`) + `/api/5` + `/login` (`0x65d4a8`), token as `?accessToken=` (`0xee0d0`, error
`请先绑定轻阅读后端`), websocket `ws(s)://<host>/api/5/?id=<id>&sg=1` (`0x2acdc8`, class `QreadWebsocket`). Prefs keys
`Qreadusername`, `Qreadpassword`, `Qreadurl`, `Qreadisbind`. Command names used over it (Legado-style web service):
`getUserInfo getBookshelfNew getBookshelfPage saveBookProgress addToBookshelf getBookinfo getBookinfo2 getChapterListNew
getBookContentNew fetchBook fetchBookContent searchBook exploreBook importBookPreview urlsaveBook getBookSourcesNew
getBookSourcesPage getbookSources getbookSourcejson editbookSources saveBookSourcesv2 delbookSource(s) startbookSource(s)
stopbookSource(s) editsourcegroup getBookSourcesExploreUrl getRssSources getRssSourcessNew getRssSourcessPage getRssContent
editRssSources saveRssSources delRssSource(s) startRssSource(s) stopRssSource(s) editrsssourcegroup getRsssortUrls
putLoginInfo getLoginInfo putRssLoginInfo getRssLoginInfo getSourcesloginui getRssSourcesloginui setVariable getVariable
setRssVariable getRssVariable setbookVariable getbookVariable cookie getCookies saveCookies cleancookies noCookies cleancaches
imageDecode svgtopng getopenurl tts_analysis findaction action rssaction rssshouldOverrideUrlLoading changeSourcePermission
savehtml payAction2` (`payAction2` goes with the book-source chapter purchase, `购买章节`, not the app membership **[infer]**).
A debug/MCP-style endpoint set (`/healthz`, `/debug`, `/source`) is documented in the strings at `pp+0x5a070…`.

## 3. Other services
The replica's own implementation of sections 1 and 3 is `server/` (deployed, see `server/README.md`); the theme plaza contract below was
read from `0x1099b00` (list), `0x10e1120` (categories), `0x1040c64` (detail) and the parsers `0x81b908`, `0x6cfab8`, `0x6cfff0`:
`GET /public/themes?page&limit&category_id` → `{code:200, data:{items, total, page, limit, max_page}}`, item = `{id, name, description,
category_id, category{id,name}, zip_path, layout_path, image_path, version, author, theme_mode, created_at, updated_at}`;
`GET /public/categories` → `{code, data:[{id,name}]}`; `GET /public/themes/<id>`; files are downloaded from `<theme host> + <path>`;
failures carry `message`, success is `code < 400`.

| Service | Use |
| --- | --- |
| `http://scheduler2.qread.xyz/api/allocate` (query `user`, `platform`, `appid`, `t`) | allocates a server for the Legado-compatibility engine (`0xe8347c`); errors `获取服务器失败`, `兼容层初始化失败` |
| `https://api.qread.xyz/static/down.json`, `…/qq.json` | static JSON: download list, community links |
| `http://theme2.qread.xyz/public/themes`, `/public/categories`, `/public/themes/<id>` | theme plaza (download is a member feature) |
| `http://yuan.qread.xyz/get-html?url=` | HTML fetch proxy used by sources |
| `http://tts.qread.xyz/edge.html` | Edge TTS helper page |
| `wss://openspeech.bytedance.com/api/v1/tts/ws_binary` | ByteDance TTS (user's own key) |
| `https://api.xiaomimimo.com/v1` and OpenAI-compatible `/chat/completions` | AI chat / purification (user's own key) |
| gRPC `/common.WebBookService/BookStream` | bidirectional stream to a server-side Legado engine (not the membership channel); recovered `.proto` and notes in `docs/proto/` |
| Baidu Pan, Weiyun, CloudDrive2, WebDAV | network-drive features (member-gated in the UI) |
| `https://www.qread.xyz/ai.html`, `docs.html`, `jquery.min.js` | static web pages |

### Update check `check_update` [code 0x1078878, server]
`GET <base>check_update?platform=ios&version=<PackageInfo.buildNumber>&t=<ms>` (no token). Reply `{code, updateUrl, description}`:
`code` 0 means a newer build exists (the app then shows 发现新版本 / 更新内容: `description` / 暂不更新 / 立即更新 → opens `updateUrl`);
any other code, and any network error, means "no update" (关于 page: 已是最新版本). The app asks on the 关于 page (检查更新) and at
main-page start-up when the prefs key `updateReminder` is unset or `"true"` (更新提醒 switch). The owner's server answers from the release
set with `qread-admin set-update <file.json>` (`{"version":"1.0.1","build":2,"notes":"…","url":"https://…","platform":"ios"}`;
`platform` optional): `code 0` plus `updateUrl` = url, `description` = notes (also `version`, `build`) when `build` is greater than the
`version` parameter, else `{code: -1, errorMsg: "已是最新版本"}`. `set-update --clear` withdraws it, `show-update` prints it.

## 4. WebDAV book repository (replica addition, `server/src/dav.mjs`)
`<base>/dav/…` is a per-user WebDAV store for the app's 云端仓库 (the original expected the user's own WebDAV server). Basic auth with
the username (or e-mail) and either the account password or a live session token — the app's 「使用轻阅读账号服务器」 creates a
网盘管理 entry with the `tockenid` as password, so nothing is typed. Methods: OPTIONS, PROPFIND (Depth 0/1), HEAD, GET, PUT, DELETE,
MKCOL, MOVE. Files live in `<dataDir>/dav/<user id>/…`; limits `QREAD_DAV_MAX_FILE_BYTES` (64 MB) per file and `QREAD_DAV_QUOTA_BYTES`
(2 GB) per user. The app mirrors `books/` into `<backupDir>` (default `/books`) and fetches a missing local file back from there.
