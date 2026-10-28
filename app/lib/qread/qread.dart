// qread/qread.dart — client of the user's own 轻阅读 backend (a Legado engine running as a web service that the user hosts and
// binds on the 轻阅读后端绑定 page). Nothing here talks to qread.xyz: every request goes to the base url the user typed.
//
// Original:
//   `Qread` (statics `baseurls` 0x3a98, `allowchange` 0x3a70, `_encrypter` 0x3ac0, `_iv` 0x3ab8)
//     login url  0x65d4a8  `<baseurls[i]>/api/5/login`, error `baseUrl不存在`
//     api url    0xee0d0   `<baseurls[0]>/api/5<path>?accessToken=<token>`, error `请先绑定轻阅读后端`
//     bind       0x100d894 tries every base url (`尝试登陆,i:`), stores `accessToken`, `绑定失败:` / `未获取到站点`
//     login body 0x100e0f0 `{username, password, model}` -> `{isSuccess, data:{accessToken,…}, errorMsg}`
//     getUserInfo 0xf1adfc `/getUserInfo` -> data.userInfo.username …; `qreadcaneditsource` 0xf1acf4; `allowchange:` 0xf1ac64
//   File-store keys carry the device id (docs/SETTINGS.md §1): Qreadisbind<appid>, Qreadurl<appid>, Qreadusername<appid>,
//   Qreadpassword<appid>, accessToken<appid>, baseurls<appid>, qreadcaneditsource<appid>.
//   `QreadWebsocket` (0x2ad0ac, 0xf1a430): `ws(s)://<host>/api/5/<name>?id=<token>&sg=1` (0x2acdc8) — the backend pushes
//   device-side jobs (toast, startBrowser, webview, getVerificationCode, proxied get/post/head, copyText, …) to the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import '../common/common.dart';
import '../storage/storage.dart';
import '../util/http.dart';
import '../util/toast.dart';
import '../util/webbook/util/client_app.dart';
import 'http.dart';
import 'qread_jobs.dart';

/// A failed backend call; [message] is the backend's `errorMsg` (or the original's client-side text).
class QreadException implements Exception {
  final String message;
  const QreadException(this.message);
  @override
  String toString() => message;
}

abstract class Qread {
  /// Candidate base urls of the bound backend (the first one is used for requests).
  static List<String> baseurls = <String>[];

  /// `allowchange` pushed by the backend (`allowchange:` 0xf1ac64).
  static int allowchange = 0;
  static bool isbind = false;
  static String url = '';
  static String username = '';
  static String accessToken = '';

  /// `qreadcaneditsource`: the backend lets this user edit its sources.
  static bool caneditsource = false;

  /// Bumped on bind / unbind so pages can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _k(String key) => '$key${Common.appid}';

  /// Reads the bound state from the file store.
  static Future<void> load() async {
    for (final k in ['Qreadisbind', 'Qreadurl', 'Qreadusername', 'Qreadpassword', 'accessToken', 'baseurls', 'qreadcaneditsource']) {
      Storage.keepOnClean(_k(k));
    }
    isbind = (await Storage.read(_k('Qreadisbind'))) == 'true';
    url = await Storage.read(_k('Qreadurl'));
    username = await Storage.read(_k('Qreadusername'));
    accessToken = await Storage.read(_k('accessToken'));
    caneditsource = (await Storage.read(_k('qreadcaneditsource'))) == 'true';
    baseurls = [for (final e in Storage.jsondecode(await Storage.read(_k('baseurls')))) if ('$e'.isNotEmpty) '$e'];
    if (baseurls.isEmpty && url.isNotEmpty) baseurls = splitUrls(url);
    revision.value++;
  }

  /// The base urls typed on the bind page: separated by commas, semicolons, whitespace or new lines; trailing `/` and a
  /// trailing `/api/5` are dropped; a missing scheme gets `http://`.
  static List<String> splitUrls(String text) {
    final out = <String>[];
    for (var u in text.split(RegExp(r'[\s,，;；]+'))) {
      u = u.trim();
      if (u.isEmpty) continue;
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) u = 'http://$u';
      while (u.endsWith('/')) {
        u = u.substring(0, u.length - 1);
      }
      if (u.endsWith('/api/5')) u = u.substring(0, u.length - 6);
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  /// 0x65d4a8: the login url of base url [i].
  static String loginUrl(int i) {
    if (i < 0 || i >= baseurls.length) throw const QreadException('baseUrl不存在');
    return '${baseurls[i]}/api/5/login';
  }

  /// 0xee0d0: `<base>/api/5<path>?accessToken=<token>[&query]`.
  static String api(String path, [String query = '']) {
    if (!isbind || baseurls.isEmpty || accessToken.isEmpty) throw const QreadException('请先绑定轻阅读后端');
    return '${baseurls.first}/api/5$path?accessToken=${Uri.encodeQueryComponent(accessToken)}$query';
  }

  /// 0x2acdc8: websocket url of [name] (`debug`, `` for the device channel).
  static String wsUrl(String name) {
    if (!isbind || baseurls.isEmpty) throw const QreadException('请先绑定轻阅读后端');
    final base = baseurls.first.replaceFirst(RegExp('^http', caseSensitive: false), 'ws');
    return '$base/api/5/$name?id=${Uri.encodeQueryComponent(accessToken)}&sg=1';
  }

  /// POSTs [body] (JSON) to the backend and returns `data`; throws [QreadException] with `errorMsg` when `isSuccess` is false.
  static Future<dynamic> post(String path, [Object? body, String query = '']) async {
    final Map<String, dynamic> r;
    try {
      r = await QHttp.post(api(path, query), body is Map<String, dynamic> ? body : {'data': body});
    } on QHttpException catch (e) {
      throw QreadException(e.message);
    }
    if (r['isSuccess'] != true) throw QreadException('${r['errorMsg'] ?? '网络错误'}');
    return r['data'];
  }

  // ------------------------------------------------------------------------------------------------------- password storage

  /// The password is kept encrypted (the original uses `Qread._encrypter`/`_iv`; its key is not copied). The replica derives
  /// an AES key from the device id and prefixes a random IV.
  static enc.Encrypter _encrypter() =>
      enc.Encrypter(enc.AES(enc.Key(Uint8List.fromList(crypto.sha256.convert(utf8.encode('qread:${Common.appid}')).bytes)), mode: enc.AESMode.cbc));

  static String encryptPassword(String plain) {
    final iv = enc.IV.fromSecureRandom(16);
    return '${iv.base64}:${_encrypter().encrypt(plain, iv: iv).base64}';
  }

  /// 0x10ce368; prints `解密失败: ` and gives '' for a damaged value.
  static String decryptPassword(String stored) {
    final i = stored.indexOf(':');
    if (i <= 0) return '';
    try {
      return _encrypter().decrypt64(stored.substring(i + 1), iv: enc.IV.fromBase64(stored.substring(0, i)));
    } catch (e) {
      debugPrint('解密失败: $e');
      return '';
    }
  }

  static Future<String> savedPassword() async => decryptPassword(await Storage.read(_k('Qreadpassword')));

  // ------------------------------------------------------------------------------------------------------------- bind / unbind

  /// 0x100d894: logs in on every base url in turn; the first that answers wins. Throws `绑定失败:…` / `未获取到站点`.
  static Future<void> bind(String urlText, String user, String password) async {
    final urls = splitUrls(urlText);
    if (urls.isEmpty) throw const QreadException('请输入后端地址');
    baseurls = urls;
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      debugPrint('尝试登陆,i:$i');
      final Map<String, dynamic> r;
      try {
        r = await QHttp.post(loginUrl(i), {'username': user, 'password': password, 'model': Common.deviceModel}, timeout: const Duration(seconds: 15));
      } catch (e) {
        lastError = '网络错误';
        continue;
      }
      final data = r['data'];
      if (r['isSuccess'] == true && data is Map && data['accessToken'] is String) {
        // the answering url goes first
        baseurls = [urls[i], ...urls.where((u) => u != urls[i])];
        accessToken = data['accessToken'] as String;
        username = user;
        url = urlText.trim();
        isbind = true;
        await Storage.write(_k('Qreadisbind'), 'true');
        await Storage.write(_k('Qreadurl'), url);
        await Storage.write(_k('Qreadusername'), username);
        await Storage.write(_k('Qreadpassword'), encryptPassword(password));
        await Storage.write(_k('accessToken'), accessToken);
        await Storage.write(_k('baseurls'), jsonEncode(baseurls));
        await refreshUserInfo();
        revision.value++;
        return;
      }
      lastError = '${r['errorMsg'] ?? '登录失败'}';
    }
    if (lastError != null) throw QreadException('绑定失败:$lastError');
    throw const QreadException('未获取到站点');
  }

  /// 0xf1adfc `/getUserInfo`: refreshes the username and the edit permission.
  static Future<void> refreshUserInfo() async {
    try {
      final data = await post('/getUserInfo', const <String, dynamic>{});
      if (data is Map) {
        final info = data['userInfo'];
        if (info is Map && info['username'] != null) username = '${info['username']}';
        // the edit permission is not part of this answer: the device channel's `source` job sets it (0x2ad0ac, `md5` == "1")
      }
    } catch (e) {
      debugPrint('getUserInfo: $e');
    }
  }

  static Future<void> setCanEditSource(bool v) async {
    caneditsource = v;
    await Storage.write(_k('qreadcaneditsource'), v ? 'true' : 'false');
  }

  static Future<void> unbind() async {
    QreadWebsocket.close();
    QreadJobs.inited = false;
    isbind = false;
    accessToken = '';
    caneditsource = false;
    for (final k in ['Qreadisbind', 'accessToken', 'qreadcaneditsource']) {
      await Storage.write(_k(k), '');
    }
    revision.value++;
  }

  /// `当前用户无法编辑轻阅读书源…` gate of the managers: true when the user may edit backend sources.
  static bool requireEdit() {
    if (isbind && caneditsource) return true;
    Toast.show('当前用户无法编辑轻阅读书源，请在后台给予权限，如未绑定后端请先绑定后端');
    return false;
  }

  @visibleForTesting
  static void resetForTests() {
    baseurls = <String>[];
    allowchange = 0;
    isbind = false;
    url = '';
    username = '';
    accessToken = '';
    caneditsource = false;
  }
}

/// The backend's device channel (0x2ad0ac). The backend sends `{msg, id, …}` jobs; the app runs them and answers with
/// `{id, data}`. Here: toast, longToast, log, copyText, allowchange, source (edit permission), get / post / head (proxied through
/// the app's HTTP client), getVerificationCode, getWebViewUA, startBrowser / startBrowserdp / showBrowser and webview through the
/// LegadoPlatform hooks; the jobs that act on pages and lists (logout, openurl, searchBook, addBook, bookmd5, rssmd5, sourcemd5, init,
/// gonggao, reLoginView, upLoginData, refreshBookInfo / refreshBookToc / refreshContent, refreshExplore) are in qread_jobs.dart;
/// any other job is answered with `/noCookies {id}` like the original.
abstract class QreadWebsocket {
  static final ValueNotifier<bool> islink = ValueNotifier<bool>(false);
  static final Random random = Random();
  static WebSocket? _ws;
  static void Function(String text)? onLog;

  /// 0xf1a430: connects (once) to the device channel.
  static Future<void> connect() async {
    if (_ws != null || !Qread.isbind) return;
    debugPrint('尝试连接服务器');
    try {
      final ws = await WebSocket.connect(Qread.wsUrl('')).timeout(const Duration(seconds: 15));
      _ws = ws;
      islink.value = true;
      debugPrint('WebSocket连接成功');
      ws.listen((m) {
        debugPrint('收到WebSocket消息: $m');
        handle('$m');
      }, onError: (Object e) {
        debugPrint('WebSocket错误: $e');
        islink.value = false;
        _ws = null;
      }, onDone: () {
        debugPrint('WebSocket连接关闭');
        islink.value = false;
        _ws = null;
      });
    } catch (e) {
      debugPrint('WebSocket连接失败: $e');
      debugPrint('网络错误，尝试更换地址');
      if (Qread.baseurls.length > 1) Qread.baseurls = [...Qread.baseurls.skip(1), Qread.baseurls.first];
    }
  }

  static void close() {
    _ws?.close();
    _ws = null;
    islink.value = false;
  }

  static void _reply(Object? id, Object? data) {
    _ws?.add(jsonEncode({'id': id, 'data': data}));
  }

  /// Runs one job; returns the reply (also sent on the socket). Public for tests.
  static Future<Object?> handle(String message) async {
    Map<String, dynamic> m;
    try {
      final v = jsonDecode(message);
      if (v is! Map) return null;
      m = Map<String, dynamic>.from(v);
    } catch (_) {
      return null;
    }
    final id = m['id'];
    final body = m['body'] is Map ? Map<String, dynamic>.from(m['body'] as Map) : m;
    Object? out;
    switch ('${m['msg']}') {
      case 'toast':
      case 'longToast':
        Toast.show('${body['str'] ?? ''}');
      case 'log':
        onLog?.call('${body['str'] ?? ''}');
      case 'copyText':
        LegadoPlatform.copyText?.call('${body['str'] ?? body['text'] ?? ''}');
      case 'allowchange':
        Qread.allowchange = int.tryParse('${body['allowchange'] ?? body['data'] ?? 0}') ?? 0;
        debugPrint('allowchange:${Qread.allowchange}');
      case 'source':
        // 0x2ad0ac: `md5` == "1" → may edit the backend's sources (0xf1acf4 stores `qreadcaneditsource`)
        await Qread.setCanEditSource('${m['md5'] ?? body['md5']}' == '1');
      case 'getWebViewUA':
        out = LegadoPlatform.webViewUserAgent ?? AppHttp.userAgent;
      case 'getVerificationCode':
      case 'getVerificationCodeusePhone':
        out = await LegadoPlatform.getVerificationCode?.call('${body['url'] ?? ''}');
      case 'startBrowser':
      case 'startBrowserdp':
      case 'showBrowser':
        out = await LegadoPlatform.startBrowserAwait?.call('${body['url'] ?? ''}', '${body['title'] ?? ''}', true);
      case 'webview':
        out = await LegadoPlatform.webView?.call(
          html: body['html'] as String?,
          url: '${body['url'] ?? ''}',
          js: body['js'] as String?,
          sourceRegex: body['urlregex'] as String?,
          overrideUrlRegex: body['overrideUrlRegex'] as String?,
        );
      case 'get':
      case 'post':
      case 'head':
        out = await proxy('${m['msg']}', body);
      default:
        String field(String k) => '${m[k] ?? body[k] ?? ''}';
        if (!await QreadJobs.run('${m['msg']}', field)) {
          debugPrint('QreadWebsocket: unsupported ${m['msg']}');
          if (m.containsKey('msg')) await QreadJobs.notHandled(field('id'));
        }
    }
    if (id != null) _reply(id, out);
    return out;
  }

  /// `_performGetRequest` / `_performPostRequest` / `_performHeadRequest` (0xf21068 / 0xf1f6b4 / 0xf2042c): the request runs on
  /// the device (its IP, its cookies) and the reply carries `{success, currentUrl, cookie, response}` or `{success:false, error}`.
  static Future<Map<String, dynamic>> proxy(String method, Map<String, dynamic> body) async {
    final url = '${body['url'] ?? ''}';
    try {
      final headers = <String, String>{};
      final h = body['header'];
      if (h is Map) h.forEach((k, v) => headers['$k'] = '$v');
      if (h is String && h.isNotEmpty) {
        final d = jsonDecode(h);
        if (d is Map) d.forEach((k, v) => headers['$k'] = '$v');
      }
      final res = await AppHttp.send(HttpRequest(
        url: url,
        method: method.toUpperCase(),
        headers: headers,
        body: body['body'] is String ? body['body'] as String : (body['body'] == null ? null : jsonEncode(body['body'])),
        followRedirects: body['move'] != false && '${body['move']}' != 'false',
        useCookieJar: '${body['isCookieJar'] ?? body['CookieJar'] ?? 'true'}' != 'false',
      ));
      return {
        'success': true,
        'currentUrl': res.url,
        'cookie': (res.headers['set-cookie'] ?? const <String>[]).join('; '),
        'response': method == 'head' ? '' : AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType),
        'code': res.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }
}
