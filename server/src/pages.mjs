// The web page of the server, served at `/` and `/vip`.
//  * opened by the app as <base>vip?tockenid=<token>  -> shows the membership status and the activation-code box (会员中心)
//  * opened in a browser without a token             -> shows a login form first, then the same page
// Plain HTML + XHR (no framework) so the app's WebView and a normal browser both work; all dynamic text is set with textContent
// and the script is a separate file, so the CSP can forbid inline script.

export const VIP_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>会员中心 · 轻悦复刻</title>
<style>
  body { margin: 0; font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; background: #f4f5f7; color: #1c1c1e; }
  .wrap { max-width: 520px; margin: 0 auto; padding: 16px; }
  .card { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px; }
  h1 { font-size: 20px; margin: 8px 0 4px; }
  .sub { color: #6b6b70; font-size: 13px; margin-bottom: 14px; }
  .row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 15px; }
  .k { color: #6b6b70; }
  input { width: 100%; box-sizing: border-box; padding: 10px; font-size: 16px; border: 1px solid #d1d1d6; border-radius: 8px; margin-top: 8px; }
  button { margin-top: 10px; width: 100%; padding: 11px; font-size: 16px; border: 0; border-radius: 8px; background: #0a84ff; color: #fff; cursor: pointer; }
  button.ghost { background: #e5e5ea; color: #1c1c1e; }
  .msg { margin-top: 8px; font-size: 14px; min-height: 20px; }
  .err { color: #d70015; } .good { color: #1a7f37; }
  ul { margin: 0; padding-left: 18px; } li { font-size: 14px; line-height: 1.7; }
  .hidden { display: none; }
</style>
</head>
<body>
<div class="wrap">
  <h1>会员中心</h1>
  <div class="sub">轻悦复刻 · 账号与会员</div>

  <div class="card hidden" id="loginBox">
    <div class="row"><span class="k">登录</span></div>
    <input id="user" placeholder="用户名 / 邮箱" autocomplete="username" autocapitalize="none">
    <input id="pass" type="password" placeholder="密码" autocomplete="current-password">
    <button id="loginGo">登录</button>
    <div class="msg" id="loginMsg"></div>
  </div>

  <div id="member" class="hidden">
    <div class="card" id="info"></div>
    <div class="card">
      <div class="row"><span class="k">激活码</span></div>
      <input id="code" placeholder="QR-XXXX-XXXX-XXXX" autocomplete="off" autocapitalize="characters">
      <button id="go">兑换</button>
      <div class="msg" id="msg"></div>
    </div>
    <div class="card">
      <div class="row"><span class="k">会员功能</span></div>
      <ul><li>云端同步（书架、书源、订阅、笔记、排版、书签）</li><li>书架与书源备份，不限设备数（非会员最多 2 台）</li><li>主题下载与应用、顶栏按钮自定义</li><li>本地引擎、网盘、AI 对话等</li></ul>
    </div>
    <button class="ghost hidden" id="logout">退出登录</button>
  </div>
</div>
<script src="/vip.js"></script>
</body>
</html>
`;

export const VIP_JS = `(function () {
  function qs(name) {
    var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search);
    return m ? decodeURIComponent(m[1]) : '';
  }
  function $(id) { return document.getElementById(id); }
  function store(k, v) { try { if (v === null) sessionStorage.removeItem(k); else sessionStorage.setItem(k, v); } catch (e) {} }
  function load(k) { try { return sessionStorage.getItem(k) || ''; } catch (e) { return ''; } }
  function deviceId() {
    try {
      var d = localStorage.getItem('qread_web_appid');
      if (!d) { d = 'web-' + Math.random().toString(16).slice(2) + Date.now().toString(16); localStorage.setItem('qread_web_appid', d); }
      return d;
    } catch (e) { return 'web-anon'; }
  }
  var fromApp = !!qs('tockenid');
  var token = qs('tockenid') || load('qread_token');

  function post(path, body, cb) {
    var x = new XMLHttpRequest();
    x.open('POST', path, true);
    x.setRequestHeader('Content-Type', 'application/json');
    x.onreadystatechange = function () {
      if (x.readyState !== 4) return;
      var r = null;
      try { r = JSON.parse(x.responseText); } catch (e) {}
      cb(r);
    };
    x.send(JSON.stringify(body));
  }
  function row(k, v) {
    var d = document.createElement('div'); d.className = 'row';
    var a = document.createElement('span'); a.className = 'k'; a.textContent = k;
    var b = document.createElement('span'); b.textContent = v;
    d.appendChild(a); d.appendChild(b); return d;
  }
  function showLogin(msg) {
    $('loginBox').className = 'card';
    $('member').className = 'hidden';
    $('loginMsg').className = 'msg err';
    $('loginMsg').textContent = msg || '';
  }
  function showMember(d) {
    $('loginBox').className = 'card hidden';
    $('member').className = '';
    var box = $('info');
    box.textContent = '';
    box.appendChild(row('账号', d.username));
    box.appendChild(row('邮箱', d.email));
    box.appendChild(row('状态', d.isvip ? '会员' : '非会员'));
    box.appendChild(row('到期时间', d.isvip ? d.vip : '—'));
    $('logout').className = fromApp ? 'ghost hidden' : 'ghost';
  }
  function refresh() {
    if (!token) { showLogin(''); return; }
    post('/getUserInfo', { tockenid: token }, function (r) {
      if (r && r.code === 0) { showMember(r.data); return; }
      if (r && r.errorMsg === 'NEED_LOGIN') { token = ''; store('qread_token', null); showLogin(fromApp ? '登录已过期，请回到 App 重新登录' : '登录已过期，请重新登录'); return; }
      showLogin('加载失败，请稍后再试');
    });
  }
  $('loginGo').onclick = function () {
    var u = $('user').value, p = $('pass').value;
    if (!u || !p) { showLogin('请输入用户名和密码'); return; }
    post('/login', { username: u, password: p, platform: 'web', model: 'browser', appid: deviceId() }, function (r) {
      if (r && r.code === 0) { token = r.data.id; store('qread_token', token); $('pass').value = ''; refresh(); }
      else showLogin((r && r.errorMsg) || '登录失败');
    });
  };
  $('pass').onkeydown = function (e) { if (e.key === 'Enter') $('loginGo').onclick(); };
  $('go').onclick = function () {
    var msg = $('msg');
    var code = $('code').value;
    if (!code) { msg.className = 'msg err'; msg.textContent = '请输入激活码'; return; }
    post('/redeem', { tockenid: token, code: code }, function (r) {
      if (r && r.code === 0) { msg.className = 'msg good'; msg.textContent = '兑换成功，到期时间 ' + r.data.expire; $('code').value = ''; refresh(); }
      else { msg.className = 'msg err'; msg.textContent = (r && r.errorMsg) || '兑换失败'; }
    });
  };
  $('logout').onclick = function () {
    post('/logout', { tockenid: token }, function () { token = ''; store('qread_token', null); showLogin(''); });
  };
  refresh();
})();
`;
