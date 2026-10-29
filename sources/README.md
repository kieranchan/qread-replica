# sources — 时光源制作工具与书源

时光源 = 一个 HTML 页面：App 把它装进隐藏 WebView，调用页面里的 `search / info / chapter / content / getfinds / find /
getloginurl / login / gethelp …`，页面通过 `window.flutter_inappwebview.callHandler(...)` 使用 App 的 http、cache、
cookie、浏览器等能力。完整约定见 [`../docs/TIME_SOURCE.md`](../docs/TIME_SOURCE.md)。

```
sdk/qyd-sdk.js            页面端 SDK：FlutterJSBridge / Http / Cache / Cookie（与第三方书源同名同签名）+ QYD 工具
build.mjs                 node build.mjs <name>  → <name>/dist/source.html + source.json（可直接导入）
runner/                   桌面运行器：node runner/run.mjs --page <file|url> <命令>（无头 Chrome + CDP，Node 实现 App 的 handler）
langge/                   大灰狼聚合书源 · qread 版（source.src.html + source.meta.json → dist/）
luis/                     路易斯聚合（自己的平台 server/src/luis，同一协议）
```

## 导入书源

**大灰狼聚合·qread 版**（需要大灰狼账号；登录在 App 内完成，cookie 由 App 保存）：

1. 把 [`langge/dist/source.json`](langge/dist/source.json) 的内容导入 App（书源管理 → 导入，粘贴 JSON 或选文件）。页面代码内嵌在
   JSON 的 `html` 里，不依赖任何托管地址。托管版 [`langge/dist/source.hosted.json`](langge/dist/source.hosted.json) 的 `html` 是
   `https://qread.forfine.me/tsy/langge.html`（服务器上 `qread-admin set-source langge dist/source.html` 更新，App 每次启动页面时重新下载，
   失败时用上次的副本）。
2. 发现页顶部：线路 / 类型（小说·听书·短剧·漫画）/ 频道 / 平台 / 搜索范围 / 段评；「登录 / 账户」打开后端登录页，登录后返回。
3. 书源 → 帮助 显示当前线路与账户；书源调试会显示每一步后端返回的原文（`text(type, …)`）。

**路易斯聚合**（你自己的平台，后端在 `server/src/luis/`，见 [`../docs/LUIS.md`](../docs/LUIS.md)）：导入
[`luis/dist/source.json`](luis/dist/source.json)（或托管版 [`luis/dist/source.hosted.json`](luis/dist/source.hosted.json)，页面在
`https://qread.forfine.me/tsy/luis.html`）。「登录 / 账户」打开 `https://qread.forfine.me/luis/login`，账号与会员中心通用；平台列表
（免费 / 登录 / 会员）由后端 `/luis/sources/config` 提供，新增适配器后 App 端无需改动。

原版记录同样可以直接导入（复刻版已实现它用到的全部 handler）：
`{"bookSourceUrl":"http://svip.langge.uk","bookSourceName":"大灰狼聚合书源","bookSourceGroup":"大灰狼-聚合","html":"http://svip.langge.uk/qydsy.html","login":true,"enabledExplore":true}`

## 在桌面上跑一个书源

```bash
cd sources/runner && npm test                      # SDK + 运行器自测（本地 fixture 站点，需要本机 Chrome/Edge）
node run.mjs --page ../langge/dist/source.html --base https://qread.forfine.me/tsy/langge finds
node run.mjs --page ../langge/dist/source.html --base https://qread.forfine.me/tsy/langge \
     --cookie https://v10.langge.uk "qttoken=…; deviceId=…" flow 斗破苍穹      # 搜索→详情→目录→正文
node run.mjs --page http://svip.langge.uk/qydsy.html --base http://svip.langge.uk search 斗破苍穹
```
命令：`ready finds find search info chapter content help loginurl login filter findfilter pay event action js flow`；
`--cache k v` 预置缓存（例如 `--cache tab 听书`），`--state <dir>` 指定缓存/cookie 目录，`--aes-key` 解 `@aes` 页面，
`--headful` 显示浏览器。stdout 是页面返回的原文，stderr 是 App 侧日志（http 请求、log/text/弹窗、console）。

## 写一个新书源

1. 复制 `langge/` 为 `<name>/`，改 `source.meta.json`（`bookSourceUrl` 唯一即可，页面在它之下加载）。
2. 在 `source.src.html` 里保留 `<!-- @sdk -->` 标记，实现入口函数；返回值用 `QYD.book / QYD.chapter / QYD.explore.*` 组装。
3. `node build.mjs <name>`，再用运行器跑 `flow`，最后导入 `dist/source.json`。
