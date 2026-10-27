# Membership system — what the IPA shows, and our own implementation

Scope (owner, 2026-10-27): the replica gets **its own** membership system on the owner's server. Nothing here
forges, replays or bypasses the original qread.xyz membership, purchase or authentication; the original service
is only read as a *design reference*. Everything below comes from static analysis of the shipped app
(`analysis/dart/index.sqlite`, built by `tools/scripts/build_index.py`).

## 1. How the original works

Membership is decided **entirely on the server**. The client holds three things and one rule:

| Piece | Where | Notes |
| --- | --- | --- |
| Session token | static field id `0x1f20` (offset `0x3e40`), prefs key `tockenid` | sent as `tockenid` with every account/cloud request |
| Device id | static field id `0x1e60`, written at app init (`appinit`, `0x10d37c0`) | sent as `appid` |
| VIP flag | static `bool`, field id `0x1f30` (offset `0x3e60`), prefs key `isvip` | **487 reads** in the decompiled code = the feature gates; written only by `applyUserinfo` (`0xf64ebc`), logout (`0x10487c4`) and the prefs restore (`0x11284a8`) |
| `Userinfo` model | `models/userinfo.dart`, size `0x40` = 7 slots | slot order (verified, `API.md`): username, `vip` (display text, static `0x1f90`), **`id` = the session token**, email, nickname, avatar_url, isvip |
| Rule | every gate | `if (!isVip) toast("…为会员功能")` — no client-side expiry check, no signature. After each login/refresh `applyUserinfo` also switches the three cloud-sync flags (`0x1f9c/0x1fa0/0x1fa4`) off when `!isvip` |

Persisted session keys (a contiguous run in the object pool, `pp+0x73e0 … 0x74b8`): `isLoggedIn`, `username`,
`tockenid`, `autoSyncEnabled`, `auto2SyncEnabled`, `autoSyncProgressEnabled`, `lastSyncTime`, `lastSyncTime2`,
`lastSyncTimer3`, `cloudbookself`, `cloudsource`, `etag`, `grouptag`, `bjetag`, `rsstag`, `sourcetag`, `isvip`,
`cloudtheme`, `cloudmark`, `groundmd5`, `svgmd5`, `markmd5`, `cloudtts`, `ttsmd5`, `email`, `nickname`, `avatar_url`.

### Flows
1. **Register**: `register_page.dart` — email, 6-digit verification code (`请输入6位数字验证码`), password. Success text
   `注册成功，请登录您的账户`. **Forgot password**: `forgetPassword(email)` then code.
2. **Login**: `login_page.dart` — `用户名/邮箱` + password; request fields `username, password, platform, model, appid`;
   response `{code, data:{username,id,vip,isvip,avatar_url,nickname,email}}` where **`id` is the session token** and `vip` the
   membership text (`永久` / a date); there is no `tockenid` key (`API.md`). Failures return `errorMsg`.
3. **Refresh**: `getUserInfo(tockenid, appid, t)` runs when the 会员中心 page is closed and from the user edit page.
4. **Purchase**: the 「我的」 page and the user settings page open `NWebviewPage` titled **会员中心** at
   `<base>vip?tockenid=<token>`. This page is rendered by **WebF** (Dart-hosted web engine, `_onJSMethodCall`), so it is
   server-hosted HTML/JS. Its JS calls the native method **`paynew`** with `vipType` and `paymentType`
   (StoreKit / third-party pay bridge); the native handler answers `ok`. After the page closes the app calls `getUserInfo`.
5. **Server-side checks** that exist as their own calls: `canOpenCloud(tockenid, t)` (cloud permission),
   `paynew(tockenid, vipType, paymentType)`.
6. **Devices**: `getloginDevice`, `removeDevice`, `getAutoDevice`, `getAuto2Device`, `removeAutoDevice`
   (list/remove logged-in and auto-backup devices). Free accounts: at most **2 backup devices**, and bookshelf backup
   and cloud bookshelf cannot both be on.
7. **Account**: `updateNickname`, `updateAvatar?tockenid=` (multipart, field `file`, returns `avatar_url`),
   `imgupload?md5=&tockenid=` + `hasimg` (avatar dedupe by md5), `changePassword(oldpassword,newpassword)`,
   `logout`, `cleanuser` (delete account data).

## 2. Feature gates (client side)

`isvip == false` blocks the following. File = owner of the check (blutter attribution). The 487 reads of the flag are
concentrated in the reader (`content.dart` 148, `list.dart` 97, `listcontroller.dart` 31, `bottom_menu.dart` 27,
`novel_view.dart` 18, `read_more_setting.dart` 21); those are silent: non-members get the default behaviour instead of a toast.

| Feature | Message | File / class |
| --- | --- | --- |
| Cloud sync switches (bookmarks, book sources, RSS, notes, theme, TTS, …) | `此功能为会员功能`, `云端功能需要会员权限，开启后将自动同步数据到云端，确保多设备数据一致` | `pages/user/cloud_setting_page.dart` `_CloudSettingPageState` (6 gates) |
| Book-source backup; bookshelf backup beyond 2 devices | `书源备份是会员功能。`, `非会员最多只能备份 2 个设备…` | `pages/user/backup_setting_page.dart` `_BackupSettingPageState` |
| Themes: manage / download / apply | `主题为会员功能！`, `仅会员允许下载主题`, `仅会员允许应用主题` | `pages/theme/theme_manager_page.dart`, `theme_detail_page.dart`, `theme_item_widget.dart` |
| Local TTS engine | `本地引擎仅 VIP 可用` | `pages/tts/tts_setting.dart` |
| Local compatibility engine (阅读兼容层, `@yuedu` sources) | `您好，本地引擎仅支持会员使用。`, `阅读兼容层目前为测试功能，可能会在后续版本归于仅会员使用` | `util/source/baswebview.dart`, `data/bookself.dart` |
| Reader top-bar button customisation | `此功能为会员专享，开通会员后可自定义顶栏按钮` | `pages/read/pages/novel/read_more_setting.dart` |
| AI chat in the reader | `当前功能仅对会员开放` | `pages/read/pages/novel/views/ai_chat_sheet.dart` |
| Network drive (WebDAV/Baidu/Weiyun/CloudDrive2) | `网盘为会员独享功能！` | `pages/webdav/webdav_manager_page.dart` |
| SVG icon sets: edit / export / import | `仅会员可编辑/导出/导入` | `pages/setting/choose_svg.dart` |
| Reader customisation (custom header/footer texts, top-menu buttons, layout options; non-members fall back to defaults) | (silent) | `pages/read/pages/novel/{list,content}.dart`, `views/bottom_menu.dart`, `read/util/listcontroller.dart`, `util/epub/epub_page_counter.dart` |
| Membership entry points | `会员中心`, `立即开通` | `pages/me_page.dart`, `pages/user/user_setting_page.dart` |

Not membership: book-source chapters have their own `isPay`/`isVip` flags (paid novel chapters, `购买章节`); they
live in `pages/read/pages/novel/views/top_menu.dart` and the source engine and are unrelated to the app account.

## 3. What the IPA does not contain
Pricing, `vipType` values, the purchase page itself, server-side expiry logic, code redemption — all live on the
server. The replica therefore needs its own definition of all of them; sections 4–5 are our design.

## 4. Our design (own server)

* **Model**: user(email, password hash, nickname, avatar) + `vip_until` (UTC ms). `isvip = vip_until > now` is
  computed on every response; the client never decides expiry. `vip` string = text shown in the UI (a date, or `永久` for a lifetime grant, empty for non-members).
* **How members are made**: (a) activation codes issued by the owner (`days`, optional expiry, single use, stored
  hashed), redeemed on the 会员中心 page — this replaces `paynew`/StoreKit; (b) owner/admin grant API. No payment
  processing is built or planned.
* **会员中心 page**: server-hosted HTML at `/vip?tockenid=…` (status, expiry, redeem box, device list), written for the
  WebF subset and answering the same JS bridge call (`paynew` with a code payload) so the native handler stays 1:1.
* **Gates**: unchanged client logic (one bool). The server additionally exposes `canOpenCloud` and refuses cloud
  sync calls for non-members, so the gates are not client-only on our own server.
* **Wire contract**: exactly the calls listed in `API.md` (names, `tockenid`/`appid`/`t` fields, `{code,data}` replies),
  so the replica's `UserApi` port does not change.
* **Safety**: tokens random 192-bit, stored hashed; login rate-limit; code-guess rate-limit; HTTPS only (Caddy/Cloudflare
  as in the dgtf2 server notes); no personal data beyond email/nickname/avatar.

## 5. Build order — status 2026-10-27
1. **Done.** `server/` (Node 24, `node:sqlite`, no dependencies): accounts, tokens, devices, `getUserInfo`, `login`, `register` (invite codes).
2. **Done.** Membership: `vip_until`, activation codes (also through the app's `paynew` call), admin CLI, `/vip` page, `canOpenCloud`, server-side cloud gate.
3. **Done (first version).** Cloud sync: five list kinds with etag / update-url / list, generic items, md5, reading progress, backup devices;
   theme plaza; static files. Semantics that are only inferred are marked in `API.md`; the app's backup-upload path is not implemented.
4. **Done.** 15 end-to-end tests (`server/test`), live smoke test `server/tools/smoke.mjs`; deployed to the Korean VM as `https://qread.forfine.me`
   (`server/README.md`, runbook in the infra repo `docs/33`).
5. **Open.** Verify the update-url semantics with the replica app once the `UserApi` port exists; add the
   backup-upload endpoints when the backup feature is ported; optional SMTP for `getEmailCode`/`forgetPassword`.
