# qread-server

The owner's own backend for the qread replica: accounts, membership (activation codes), the 会员中心 page, cloud sync,
theme plaza and static files. Node >= 24, **no dependencies** (`node:http`, `node:sqlite`, `node:crypto`), one SQLite
file. The wire contract is the one recovered from the original app (`../docs/API.md`); nothing of the original service is
contacted or reproduced.

```
src/server.mjs   HTTP entry (routes below)            src/admin.mjs   admin CLI (SQLite directly, no HTTP admin)
src/userapi.mjs  account / membership / cloud calls   src/service.mjs  domain logic (users, tokens, vip, codes, blobs)
src/themes.mjs   theme plaza                          src/pages.mjs    会员中心 page    src/backup.mjs  nightly backup
test/api.test.mjs  20 end-to-end tests (in-memory DB)   tools/smoke.mjs  smoke test against a deployed server
deploy/          systemd units, Caddy site block, bootstrap + deploy scripts
```

## Run / test
```bash
npm test                                   # node --test, ~2 s
QREAD_DATA_DIR=./data QREAD_BASE_URL=http://127.0.0.1:8920 node src/server.mjs
node src/admin.mjs help
```
Environment: `QREAD_HOST` (127.0.0.1), `QREAD_PORT` (8920), `QREAD_DATA_DIR` (./data), `QREAD_BASE_URL` (public origin, used in
avatar/theme URLs), `QREAD_REGISTER` (`invite` | `closed`), `QREAD_MAIL` (`off`; no mail is ever sent), `QREAD_TOKEN_TTL_DAYS`
(365), `QREAD_FREE_BACKUP_DEVICES` (2), `QREAD_CLOUD_NEEDS_VIP` (1), `QREAD_TRUST_PROXY` (1: use `CF-Connecting-IP` from loopback).

## Behaviour
* **Accounts**: `register` needs an admin-issued 6-digit invite code in the `code` field (the app's email-code box); `getEmailCode`
  sends nothing; `forgetPassword` is refused (admin resets with the CLI). Passwords scrypt-hashed, session tokens random 192 bit
  stored as SHA-256, one token per `appid` (re-login replaces it), 365-day expiry, login and code attempts rate limited.
* **Userinfo contract**: `login`/`getUserInfo` return `username, id, vip, isvip, avatar_url, nickname, email` where `id` is the session
  token (the app stores that slot as `tockenid`, verified in the decompiled code, `docs/API.md`) and `vip` is the membership text (`""` for
  non-members, a date, or `永久` for grants over 50 years); extra keys `userId`, `vipUntil` are ignored by the app.
* **Membership**: `vip_until` per user, `isvip = vip_until > now` evaluated on every call. Members come from activation codes
  (`QR-XXXX-XXXX-XXXX`, single use, stored hashed, optional expiry) redeemed on the 会员中心 page (`POST /redeem`) or through the app's
  `paynew` call with `paymentType=code` and the code in `vipType`; or from the admin CLI. There is no payment processing.
* **Cloud sync** (members only, enforced server side): five list kinds (bookshelf, RSS, book sources, notes, groups) with the
  etag / update-url / list triple, generic items (`getItemJson`, `getItemMd5`, `setItemJsonFile`), reading progress (`addreads`,
  `autopos`). Blobs are stored as the client sends them; the etag is the MD5 of the content. Lists are uploaded through
  `setItemJsonFile` with `item` = `books|rss|sources|notes|groups`.
* **Device backups** (书架备份 for every account, free accounts keep 2 devices; 书源备份 for members): `openAuto` / `newopenAuto2`
  (`st` 0 = register, 1 = re-open, fails when the device was removed) answer upload urls `<base>/autobackup/<key>`; the app
  `PUT`s its JSON there; `getAutoDevice` / `getAuto2Device` list the devices, `getBookSelf` / `getSources` / `getRss` (`appid` = the
  backup device) answer the same url for `GET` (404 until the first upload); `removeAuto*Device` deletes the device and its data.
* **Theme plaza**: `GET /public/themes?page&limit&category_id`, `/public/themes/:id`, `/public/categories`, files under `/public/files/`
  (`{code: 200, data}` replies). Add content with `admin add-theme`.
* **Web page**: `GET /` (and `/vip`) is the 会员中心 page: opened by the app with `?tockenid=` it shows the status and the activation-code box; opened in a
  browser it first asks for username/password. `POST /diag` receives the app's self-check results (`admin list-diag`).
* **Other**: `/images/*` (avatars, uploads), `/static/down.json`, `/static/qq.json` (`admin set-static`), `/healthz`, `/api/allocate` (stub: the
  compatibility-engine allocator is not provided), `check_update` (always "no update").
* **Not implemented / unknown**: `autopos` payload semantics beyond what `docs/API.md` records, the `yuan` HTML proxy, the Edge TTS page, the bound 轻阅读 `/api/5` backend. Unknown
  endpoints answer 404 and are logged (`{"unsupported": name}`) so missing calls show up in the journal.

## Admin CLI
`node src/admin.mjs help` (on the VM: `qread-admin help`). Typical: `create-user <name> <email> --random --days 3650`,
`make-codes vip 30 --count 5`, `make-codes invite --count 3 --valid-days 7`, `grant <user> <days>`, `list-users`, `delete-user <user>`,
`add-theme --name … --zip … --image …`.

## Deploy (Korean VM, shared with the td2 game server)
(set `QREAD_SSH_TARGET=user@host` or `deploy/target.env`, git-ignored) `bash deploy/deploy.sh --bootstrap` the first time (service user `qread`, `/var/lib/qread`, `/etc/qread/qread.env`, units, a
Caddy site block imported from `/etc/caddy/conf.d/`), then `bash deploy/deploy.sh`; `--rollback` flips to the previous release.
Releases in `/srv/qread/releases/<ts>` (3 kept), `current` symlink, health check with automatic rollback, nightly backup
(`qread-backup.timer`, 14 copies in `/var/lib/qread/backups`). Public entry `https://qread.forfine.me` (Cloudflare orange cloud,
Caddy `tls internal`, origin reachable only from Cloudflare ranges; no basic auth because the app uses its own tokens).
`node tools/smoke.mjs https://qread.forfine.me` runs 15 checks end to end and deletes its user.
