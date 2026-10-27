// The 会员中心 page (opened by the app as <base>vip?tockenid=<token>) and its script. Plain HTML + XHR so the
// app's WebF renderer and a normal browser both work. All dynamic text is set with textContent.

export const VIP_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>会员中心</title>
<style>
  body { margin: 0; font-family: -apple-system, "PingFang SC", sans-serif; background: #f4f5f7; color: #1c1c1e; }
  .wrap { max-width: 520px; margin: 0 auto; padding: 16px; }
  .card { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px; }
  h1 { font-size: 20px; margin: 8px 0 16px; }
  .row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 15px; }
  .k { color: #6b6b70; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 10px; font-size: 13px; background: #e5e5ea; }
  .badge.on { background: #ffe58f; color: #613400; }
  input { width: 100%; box-sizing: border-box; padding: 10px; font-size: 16px; border: 1px solid #d1d1d6; border-radius: 8px; }
  button { margin-top: 10px; width: 100%; padding: 11px; font-size: 16px; border: 0; border-radius: 8px; background: #0a84ff; color: #fff; }
  #msg { margin-top: 8px; font-size: 14px; min-height: 20px; }
  .err { color: #d70015; } .good { color: #1a7f37; }
  ul { margin: 0; padding-left: 18px; } li { font-size: 14px; line-height: 1.7; }
</style>
</head>
<body>
<div class="wrap">
  <h1>会员中心</h1>
  <div class="card" id="info"><div class="row"><span class="k">状态</span><span>加载中…</span></div></div>
  <div class="card">
    <div class="row"><span class="k">激活码</span></div>
    <input id="code" placeholder="QR-XXXX-XXXX-XXXX" autocomplete="off" autocapitalize="characters">
    <button id="go">兑换</button>
    <div id="msg"></div>
  </div>
  <div class="card">
    <div class="row"><span class="k">会员功能</span></div>
    <ul><li>云端同步（书架、书源、订阅、笔记、排版、书签）</li><li>书架与书源备份，不限设备数（非会员最多 2 台）</li><li>主题下载与应用、顶栏按钮自定义</li><li>本地引擎、网盘、AI 对话等</li></ul>
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
  var token = qs('tockenid');
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
  function show(d) {
    var box = document.getElementById('info');
    box.textContent = '';
    box.appendChild(row('账号', d.username));
    box.appendChild(row('邮箱', d.email));
    box.appendChild(row('状态', d.isvip ? '会员' : '非会员'));
    box.appendChild(row('到期时间', d.isvip ? d.vip : '—'));
  }
  function refresh() {
    post('/getUserInfo', { tockenid: token }, function (r) {
      if (r && r.code === 0) { show(r.data); return; }
      var box = document.getElementById('info'); box.textContent = '';
      box.appendChild(row('状态', (r && r.errorMsg) === 'NEED_LOGIN' ? '登录已过期，请重新登录' : '加载失败'));
    });
  }
  document.getElementById('go').onclick = function () {
    var msg = document.getElementById('msg');
    var code = document.getElementById('code').value;
    if (!code) { msg.className = 'err'; msg.textContent = '请输入激活码'; return; }
    post('/redeem', { tockenid: token, code: code }, function (r) {
      if (r && r.code === 0) { msg.className = 'good'; msg.textContent = '兑换成功，到期时间 ' + r.data.expire; refresh(); }
      else { msg.className = 'err'; msg.textContent = (r && r.errorMsg) || '兑换失败'; }
    });
  };
  refresh();
})();
`;
