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
| `lib/models/{userinfo,logindevice}.dart` | `Userinfo` (original slot order: JSON `id` is the session token, `vip` the membership text), `LoginDevice`, `Autodevice` |
| `lib/storage/storage.dart`, `lib/common/common.dart`, `lib/init/appinit.dart` | prefs wrapper, API base / device id, start-up |
| `lib/pages/` | `login_page`, `register_page` (the 6-digit code is an admin invite code), `forgot_password_page`, `me_page` (会员中心 entry, 立即开通), `user/user_setting_page`, `user/user_edit_page`, `user/cloud_setting_page` (member-only switches), `web/nwebview.dart` (opens `<base>vip?tockenid=`), `main_page` shell |
| `lib/util/vip.dart` | `Vip.require()` — the one-line member gate (`此功能为会员功能`) |

Deviations from the original, on purpose: the 会员中心 page is a standard WebView (the original uses WebF) because the
owner's page is plain HTML; `appid` falls back to a stored random id when the device plugin has none; `UserSession` also persists the vip text
(`vipText`) for offline display. Everything else in the original (book shelf, reader, sources, themes, TTS, AI, ...) is Phase 2.

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

## Self-check and UI tests without a phone
* `lib/pages/self_check_page.dart` (「诊断自检」 on the me page): connectivity, account, member gate, device list and the cloud
  round trip; `上报到服务器` posts the results to `diag`, the owner reads them on the server with `qread-admin list-diag`.
* `integration_test/app_flow_test.dart` + `test_driver/`: the whole flow (signed out → login → gated switch → activation code →
  member → self-check → 会员中心 web view) on an iOS Simulator. `.github/workflows/ios-ui-test.yml` starts the real server on the
  macOS runner, runs it with `flutter drive` and uploads a screenshot of every step (`ui-screenshots` artifact, 14 days).
  First green run: 4.5 min, simulator iPhone18,1 (1206×2622).

## iOS
No Mac here: `.github/workflows/ios-unsigned.yml` (repo root) builds `flutter build ios --release --no-codesign` on a macOS
runner and uploads `newread-unsigned.ipa`; install with Sideloadly. The repository is the private `kieranchan/qread-replica` (root = `qread/`, only `app/`, `server/`, `docs/`, the workflow). Windows desktop is not buildable locally (Visual Studio's desktop workload is not installed) and is not needed.
