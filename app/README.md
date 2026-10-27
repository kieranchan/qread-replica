# newread — the replica app (Flutter 3.44.9 / Dart 3.12.2)

Package name `newread`, like the original, so `lib/` paths mirror `package:newread/...` of the decompiled app
(`analysis/skeleton/`). Bundle id `com.kieranchan.qreadreplica.newread`, display name 轻悦复刻, iOS 15+.

## Phase 1 status (account + membership)
Implemented against the owner's server (`../server`, live at `https://qread.forfine.me/`; override with
`--dart-define=QREAD_BASE_URL=http://127.0.0.1:8920/`):

| File | What |
| --- | --- |
| `lib/api/userapi.dart` | every account / membership / cloud-sync call of the recovered contract (`docs/API.md`): login, register, getEmailCode, forgetPassword, getUserInfo, logout, cleanuser, updateNickname, updateAvatar, changePassword, devices, canOpenCloud, paynew/redeem, the five synced lists (etag / update-url / list), getItemJson / getItemMd5 / setItemJsonFile |
| `lib/qread/http.dart` | POST helper (Dio, JSON body, multipart for files) |
| `lib/data/user.dart` | `UserSession`: the statics (token, VIP flag, sync switches), prefs persistence under the original keys, `apply` / `restore` / `clear` / `refresh`, the "non-members get the cloud switches forced off" rule |
| `lib/models/{userinfo,logindevice}.dart` | `Userinfo` (token is read from the `vip` JSON key), `LoginDevice`, `Autodevice` |
| `lib/storage/storage.dart`, `lib/common/common.dart`, `lib/init/appinit.dart` | prefs wrapper, API base / device id, start-up |
| `lib/pages/` | `login_page`, `register_page` (the 6-digit code is an admin invite code), `forgot_password_page`, `me_page` (会员中心 entry, 立即开通), `user/user_setting_page`, `user/user_edit_page`, `user/cloud_setting_page` (member-only switches), `web/nwebview.dart` (opens `<base>vip?tockenid=`), `main_page` shell |
| `lib/util/vip.dart` | `Vip.require()` — the one-line member gate (`此功能为会员功能`) |

Deviations from the original, on purpose: the 会员中心 page is a standard WebView (the original uses WebF) because the
owner's page is plain HTML; `appid` falls back to a stored random id when the device plugin has none; `Userinfo` has an extra
`vipExpire`. Everything else in the original (book shelf, reader, sources, themes, TTS, AI, ...) is Phase 2.

## Tests (`flutter test`, 18)
* `test/session_test.dart` — Userinfo parsing, apply/restore/clear, the membership rule on the cloud switches.
* `test/pages_test.dart` — 「我的」 for signed-out / non-member / member, member-only cloud switch, login validation.
* `test/contract/server_contract_test.dart` — spawns the real `../server` with a temp database and drives `UserApi` through
  register → login → non-member gates → activation code → cloud round trips → profile → password change → logout. Skipped when
  `node` (>= 24) or `../server` is missing.

```powershell
. ..\env.ps1            # flutter on PATH, PUB_CACHE inside qread
flutter analyze; flutter test
```

## iOS
No Mac here: `.github/workflows/ios-unsigned.yml` (repo root) builds `flutter build ios --release --no-codesign` on a macOS
runner and uploads `newread-unsigned.ipa`; install with Sideloadly. The repository is the private `kieranchan/qread-replica` (root = `qread/`, only `app/`, `server/`, `docs/`, the workflow). Windows desktop is not buildable locally (Visual Studio's desktop workload is not installed) and is not needed.
