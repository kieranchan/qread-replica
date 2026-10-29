// The web pages of 路易斯: /luis/login (sets the cookies the 时光源 page uses) and /luis/user (the user centre).
// Plain HTML, one external script (/luis/app.js) so the CSP can forbid inline script.
const STYLE = `
  body { margin: 0; font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; background: #f4f5f7; color: #1c1c1e; }
  .wrap { max-width: 560px; margin: 0 auto; padding: 16px; }
  .card { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px; }
  h1 { font-size: 20px; margin: 8px 0 4px; }
  .sub { color: #6b6b70; font-size: 13px; margin-bottom: 14px; }
  .row { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0; font-size: 15px; }
  .k { color: #6b6b70; white-space: nowrap; } .v { text-align: right; word-break: break-all; }
  input { width: 100%; box-sizing: border-box; padding: 10px; font-size: 16px; border: 1px solid #d1d1d6; border-radius: 8px; margin-top: 8px; }
  button { margin-top: 10px; width: 100%; padding: 11px; font-size: 16px; border: 0; border-radius: 8px; background: #0a84ff; color: #fff; cursor: pointer; }
  button.ghost { background: #e5e5ea; color: #1c1c1e; } button.small { width: auto; padding: 4px 10px; font-size: 13px; margin: 0 0 0 8px; }
  .msg { margin-top: 8px; font-size: 14px; min-height: 20px; } .err { color: #d70015; } .good { color: #1a7f37; }
  .tag { display: inline-block; font-size: 12px; padding: 1px 7px; border-radius: 10px; background: #e5e5ea; margin-left: 6px; }
  .tag.free { background: #e3f6e8; color: #1a7f37; } .tag.vip { background: #e8f0fe; color: #1a56db; } .tag.svip { background: #fdecd3; color: #b45309; }
  .tag.locked { background: #fde2e2; color: #b91c1c; }
  ul { margin: 0; padding-left: 18px; } li { font-size: 14px; line-height: 1.7; }
  code { background: #f0f0f3; padding: 1px 5px; border-radius: 4px; font-size: 13px; word-break: break-all; }
  .hidden { display: none; }
`;

export const LOGIN_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>路易斯 · 登录</title>
<style>${STYLE}</style>
</head>
<body>
<div class="wrap" data-page="login">
  <h1>路易斯</h1>
  <div class="sub">聚合阅读平台 · 登录后返回 App 即可使用</div>
  <div class="card">
    <input id="user" placeholder="用户名 / 邮箱" autocomplete="username" autocapitalize="none">
    <input id="pass" type="password" placeholder="密码" autocomplete="current-password">
    <button id="loginGo">登录</button>
    <div class="msg" id="loginMsg"></div>
  </div>
  <div class="card">
    <ul>
      <li>账号与会员和「轻悦复刻」的会员中心通用，没有账号请找管理员领取邀请码。</li>
      <li>在 App 的书源里点「登录」打开本页，登录成功后直接返回；在浏览器里登录可进入用户中心查看密钥与平台列表。</li>
    </ul>
  </div>
</div>
<script src="/luis/app.js"></script>
</body>
</html>`;

export const USER_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>路易斯 · 用户中心</title>
<style>${STYLE}</style>
</head>
<body>
<div class="wrap" data-page="user">
  <h1>路易斯 · 用户中心</h1>
  <div class="sub" id="who">加载中…</div>
  <div class="card" id="account"></div>
  <div class="card">
    <div class="row"><span class="k">平台</span><span class="v" id="tierNote"></span></div>
    <ul id="sources"></ul>
  </div>
  <div class="card">
    <div class="row"><span class="k">在 App 里使用</span></div>
    <ul>
      <li>导入时光源：<code id="pageUrl"></code>（书源管理 → 导入 → 粘贴链接或 JSON）。</li>
      <li>书源 → 登录 会打开本站登录页；登录后发现页顶部可切换平台、类型、搜索范围。</li>
      <li>密钥即 App 内的登录凭证（cookie <code>qttoken</code>），泄露后在此退出登录即可作废。</li>
    </ul>
  </div>
  <button class="ghost" id="logout">退出登录</button>
</div>
<script src="/luis/app.js"></script>
</body>
</html>`;

export const APP_JS = `(function () {
  function $(id) { return document.getElementById(id); }
  function qs(name) { var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search); return m ? decodeURIComponent(m[1]) : ''; }
  function post(path, body, cb) {
    var x = new XMLHttpRequest();
    x.open('POST', path, true);
    x.setRequestHeader('Content-Type', 'application/json');
    x.onreadystatechange = function () { if (x.readyState !== 4) return; var r = null; try { r = JSON.parse(x.responseText); } catch (e) {} cb(r); };
    x.send(JSON.stringify(body));
  }
  function get(path, cb) {
    var x = new XMLHttpRequest();
    x.open('GET', path, true);
    x.onreadystatechange = function () { if (x.readyState !== 4) return; var r = null; try { r = JSON.parse(x.responseText); } catch (e) {} cb(r); };
    x.send();
  }
  function row(k, v, extra) {
    var d = document.createElement('div'); d.className = 'row';
    var a = document.createElement('span'); a.className = 'k'; a.textContent = k;
    var b = document.createElement('span'); b.className = 'v'; b.textContent = v;
    if (extra) b.appendChild(extra);
    d.appendChild(a); d.appendChild(b); return d;
  }
  function copyButton(text) {
    var b = document.createElement('button'); b.className = 'small'; b.textContent = '复制';
    b.onclick = function () {
      var done = function () { b.textContent = '已复制'; setTimeout(function () { b.textContent = '复制'; }, 1500); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, function () { prompt('复制：', text); });
      else prompt('复制：', text);
    };
    return b;
  }
  var page = document.querySelector('.wrap').getAttribute('data-page');

  if (page === 'login') {
    var go = function () {
      $('loginMsg').className = 'msg';
      $('loginMsg').textContent = '登录中…';
      post('/luis/login_api', { username: $('user').value.trim(), password: $('pass').value, next: qs('next'), client: qs('source_client') || 'web' }, function (r) {
        if (!r || r.code !== 0) { $('loginMsg').className = 'msg err'; $('loginMsg').textContent = (r && r.msg) || '登录失败'; return; }
        $('loginMsg').className = 'msg good';
        $('loginMsg').textContent = '登录成功' + (r.data.isvip ? '（会员' + (r.data.vip ? '至 ' + r.data.vip : '') + '）' : '') + '，正在进入用户中心…';
        var next = (r.data && r.data.next) || '/luis/user';
        if (next.charAt(0) !== '/') next = '/luis/user';
        setTimeout(function () { location.href = next; }, 600);
      });
    };
    $('loginGo').onclick = go;
    $('pass').addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
    return;
  }

  get('/luis/user_api', function (r) {
    if (!r || r.code !== 0) { location.href = '/luis/login?next=' + encodeURIComponent('/luis/user'); return; }
    var d = r.data;
    $('who').textContent = d.username + (d.nickname && d.nickname !== d.username ? '（' + d.nickname + '）' : '') + ' · ' + (d.isvip ? '会员' + (d.vip === '永久' ? '（永久）' : '，至 ' + d.vip) : '普通用户');
    var acc = $('account');
    acc.appendChild(row('邮箱', d.email));
    acc.appendChild(row('会员', d.isvip ? (d.vip === '永久' ? '永久' : '至 ' + d.vip) : '未开通'));
    acc.appendChild(row('密钥', d.qttoken.slice(0, 4) + '…' + d.qttoken.slice(-4), copyButton(d.qttoken)));
    acc.appendChild(row('设备', d.deviceId || '—', d.deviceId ? copyButton(d.deviceId) : null));
    acc.appendChild(row('线路', d.server, copyButton(d.server)));
    acc.appendChild(row('注册时间', d.registered));
    acc.appendChild(row('今日阅读 / 累计', d.stats.today + ' / ' + d.stats.all + ' 章'));
    $('tierNote').textContent = d.isvip ? '会员：全部平台可用' : '登录用户：免费与登录平台可用，会员平台需开通会员';
    var ul = $('sources');
    d.sources.forEach(function (s) {
      var li = document.createElement('li');
      li.textContent = s.name + '（' + s.tabs.join('、') + '）';
      var t = document.createElement('span'); t.className = 'tag ' + s.tier; t.textContent = { free: '免费', vip: '登录', svip: '会员' }[s.tier] || s.tier; li.appendChild(t);
      if (!s.available) { var l = document.createElement('span'); l.className = 'tag locked'; l.textContent = '未开通'; li.appendChild(l); }
      ul.appendChild(li);
    });
    $('pageUrl').textContent = d.page_url;
    $('logout').onclick = function () { post('/luis/logout', {}, function () { location.href = '/luis/login'; }); };
  });
})();`;
