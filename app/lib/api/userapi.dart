// api/userapi.dart — account, membership and cloud-sync calls. Wire contract: docs/API.md (recovered from the original).
//
// Every call is a POST to `Common.apiBase + <name>` with a JSON map. Keys: `tockenid` (session), `appid` (device), `t` (now, ms),
// plus call arguments. Replies are `{code, data?, errorMsg?}`: code 0 = ok, -5 = nothing stored, anything else = failure.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../common/common.dart';
import '../data/cloud/auto_backup.dart';
import '../data/user.dart';
import '../models/book.dart';
import '../models/logindevice.dart';
import '../models/userinfo.dart';
import '../qread/http.dart';
import '../util/self_check.dart';
import '../util/toast.dart';

class ApiException implements Exception {
  final int code;
  final String message;
  const ApiException(this.code, this.message);
  @override
  String toString() => message;
}

/// The five synced lists: (etag call, update-url call, list call).
enum CloudKind {
  books('getEtag', 'getBookUpdateurl', 'getBooks'),
  rss('getBRssEtag', 'getBRssUpdateurl', 'getBRss'),
  sources('getBSourceEtag', 'getBSourceUpdateurl', 'getBSource'),
  notes('getBjEtag', 'getBjUpdateurl', 'getBjs'),
  groups('getGroupEtag', 'getGroupUpdateurl', 'getGroups');

  final String etagCall;
  final String updateCall;
  final String listCall;
  const CloudKind(this.etagCall, this.updateCall, this.listCall);
}

abstract class UserApi {
  static const int codeOk = 0;
  static const int codeNoData = -5;
  static const String needLogin = 'NEED_LOGIN';

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Sends one call. [auth] adds the token, [withAppid] the device id; `t` is always added.
  static Future<Map<String, dynamic>> _call(
    String name, {
    Map<String, dynamic> params = const {},
    bool auth = true,
    bool withAppid = false,
    Duration? timeout,
  }) async {
    final body = <String, dynamic>{
      if (auth) 'tockenid': UserSession.tockenid,
      if (withAppid) 'appid': Common.appid,
      ...params,
      't': _now,
    };
    final resp = await QHttp.post(Common.url(name), body, timeout: timeout);
    await _checkExpired(resp);
    return resp;
  }

  static int _code(Map<String, dynamic> r) {
    final c = r['code'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return int.tryParse('$c') ?? -1;
  }

  /// A token the server no longer knows ends the session, like the original's `登陆已过期`.
  static Future<void> _checkExpired(Map<String, dynamic> r) async {
    if (r['errorMsg'] == needLogin && UserSession.tockenid.isNotEmpty) {
      await UserSession.clear();
      Toast.show('登陆已过期', iserror: true);
    }
  }

  /// code != 0 → exception carrying `errorMsg`.
  static Map<String, dynamic> _ok(Map<String, dynamic> r, [String fallback = '获取云端失败']) {
    if (_code(r) != codeOk) {
      final msg = r['errorMsg'];
      throw ApiException(_code(r), msg is String && msg.isNotEmpty ? (msg == needLogin ? '登陆已过期' : msg) : fallback);
    }
    return r;
  }

  // ---------------------------------------------------------------- accounts (no token)

  /// `login`: name or email + password; also sends platform / model / appid. Returns the account (token inside).
  static Future<Userinfo> login(String username, String password) async {
    final r = _ok(await _call('login',
        auth: false, params: {'username': username, 'password': password, 'platform': Common.platform, 'model': Common.deviceModel, 'appid': Common.appid}));
    return Userinfo.fromJson(Map<String, dynamic>.from(r['data'] as Map));
  }

  /// `getEmailCode`: asks for the registration code (the owner's server sends nothing; the code is an admin-issued invite).
  static Future<void> getEmailCode(String email) async {
    _ok(await _call('getEmailCode', auth: false, params: {'email': email}));
  }

  static Future<void> register({required String username, required String email, required String password, required String code}) async {
    _ok(await _call('register', auth: false, params: {'username': username, 'email': email, 'password': password, 'code': code}));
  }

  static Future<void> forgetPassword(String email) async {
    _ok(await _call('forgetPassword', auth: false, params: {'email': email}));
  }

  // ---------------------------------------------------------------- accounts (token)

  /// `getUserInfo`; null on failure (the original swallows errors here). An expired token ends the session.
  static Future<Userinfo?> getUserInfo() async {
    try {
      final r = await _call('getUserInfo', withAppid: true, timeout: const Duration(seconds: 8));
      if (_code(r) != codeOk || r['data'] is! Map) return null;
      return Userinfo.fromJson(Map<String, dynamic>.from(r['data'] as Map));
    } on QHttpException {
      return null;
    }
  }

  static Future<void> logout() async {
    try {
      await _call('logout');
    } on QHttpException {
      // offline logout still clears the local session
    }
    await UserSession.clear();
  }

  /// `cleanuser`: deletes the account's cloud data.
  static Future<void> cleanUser() async {
    _ok(await _call('cleanuser'));
  }

  static Future<void> updateNickname(String nickname) async {
    _ok(await _call('updateNickname', params: {'nickname': nickname}));
    UserSession.nickname = nickname;
    await UserSession.refresh();
  }

  static Future<void> changePassword(String oldPassword, String newPassword) async {
    _ok(await _call('changePassword', params: {'oldpassword': oldPassword, 'newpassword': newPassword}));
  }

  /// `updateAvatar?tockenid=`: multipart `file`; returns the new avatar URL.
  static Future<String> updateAvatar(List<int> bytes, String filename) async {
    final r = _ok(await QHttp.postFile(Common.url('updateAvatar'), {'tockenid': UserSession.tockenid}, bytes, filename));
    final url = '${(r['data'] as Map)['avatar_url']}';
    UserSession.avatarUrl = url;
    await UserSession.refresh();
    return url;
  }

  static Future<List<LoginDevice>> getLoginDevices() async {
    final r = _ok(await _call('getloginDevice'));
    return [for (final d in (r['data'] as List)) LoginDevice.fromJson(Map<String, dynamic>.from(d as Map))];
  }

  static Future<void> removeDevice(String appid) async {
    _ok(await _call('removeDevice', params: {'appid': appid}));
  }

  /// Backup devices: [kind] 1 = `getAutoDevice`, 2 = `getAuto2Device`.
  static Future<List<Autodevice>> getAutoDevices(int kind) async {
    final r = _ok(await _call(kind == 2 ? 'getAuto2Device' : 'getAutoDevice'));
    return [for (final d in (r['data'] as List)) Autodevice.fromJson(Map<String, dynamic>.from(d as Map))];
  }

  static Future<void> removeAutoDevice(int kind, String appid) async {
    _ok(await _call(kind == 2 ? 'removeAuto2Device' : 'removeAutoDevice', params: {'appid': appid}, withAppid: false));
  }

  // ---------------------------------------------------------------- device backups (书架备份 / 书源备份)

  /// `openAuto` (0xf223ac): `{tockenid, appid, st, t}`; `data` = the upload url of this device's bookshelf backup, kept in
  /// [AutoBackup.booksUrl]. [st] is `"0"` when the user switches the backup on, `"1"` when the app re-opens it at start-up.
  /// A failure switches `autoSyncEnabled` off (persisted) and throws with `errorMsg`, as the original does.
  static Future<String> openAuto({String st = '0'}) async {
    final r = await _call('openAuto', withAppid: true, params: {'st': st});
    if (_code(r) == codeOk && r['data'] is String) {
      AutoBackup.booksUrl = r['data'] as String;
      return AutoBackup.booksUrl;
    }
    await UserSession.setSwitch(PrefKeys.autoSyncEnabled, false);
    throw ApiException(_code(r), '${r['errorMsg'] ?? '开启书架备份失败'}');
  }

  /// `newopenAuto2` (0xf226c4): as [openAuto] for the source backup; `data` = `{source, rss}` upload urls
  /// ([AutoBackup.sourceUrl] / [AutoBackup.rssUrl]). A failure switches `auto2SyncEnabled` off.
  static Future<({String source, String rss})> newopenAuto2({String st = '0'}) async {
    final r = await _call('newopenAuto2', withAppid: true, params: {'st': st});
    final d = r['data'];
    if (_code(r) == codeOk && d is Map) {
      AutoBackup.sourceUrl = '${d['source'] ?? ''}';
      AutoBackup.rssUrl = '${d['rss'] ?? ''}';
      return (source: AutoBackup.sourceUrl, rss: AutoBackup.rssUrl);
    }
    await UserSession.setSwitch(PrefKeys.auto2SyncEnabled, false);
    throw ApiException(_code(r), '${r['errorMsg'] ?? '开启书源备份失败'}');
  }

  /// `getBookSelf` (0xfa8894): `{tockenid, appid = the backup device, t}` → `data` = the download url of that device's bookshelf
  /// backup, which is fetched and parsed as a book list. A failure shows `获取书架书籍失败:<e>` and yields an empty list.
  static Future<List<Book>> getBookSelf(String appid) async {
    try {
      final r = await _call('getBookSelf', params: {'appid': appid});
      if (_code(r) != codeOk) return <Book>[];
      final text = await downloadBackup('${r['data'] ?? ''}');
      final v = jsonDecode(text);
      return [for (final e in v as List) if (e is Map) Book.fromJson(Map<String, dynamic>.from(e))];
    } catch (e) {
      Toast.show('获取书架书籍失败:$e', iserror: true);
      return <Book>[];
    }
  }

  /// `getSources` (0x105127c) / `getRss` (0x1050ff4): `{tockenid, appid, t}` → the download url of the device's source / RSS
  /// backup. Throws `获取备份失败` (after logging `获取备份失败:<e>`) on any failure.
  static Future<String> getSources(String appid) => _backupUrl('getSources', appid);
  static Future<String> getRss(String appid) => _backupUrl('getRss', appid);

  static Future<String> _backupUrl(String name, String appid) async {
    try {
      final r = await _call(name, params: {'appid': appid});
      if (_code(r) != codeOk) throw ApiException(_code(r), '${r['errorMsg'] ?? '获取备份失败'}');
      return '${r['data'] ?? ''}';
    } catch (e) {
      debugPrint('获取备份失败:$e');
      throw ApiException(-1, '获取备份失败');
    }
  }

  /// `putCos` of the HTTP worker (0xe13cdc): PUTs a backup to an upload url. 413 → `当前请求内容过多，超出服务器限制`,
  /// 403 → `当前请求被拦截，请联系管理员关闭防火墙`, other failures `网络错误:  <e>`.
  static Future<void> putBackup(String url, String body) async {
    Response<dynamic> r;
    try {
      r = await QHttp.dio.put<dynamic>(url, data: body, options: Options(contentType: Headers.jsonContentType));
    } on DioException catch (e) {
      throw ApiException(-1, '网络错误:  ${e.message ?? e.type.name}');
    }
    final s = r.statusCode ?? 0;
    if (s == 413) throw const ApiException(413, '当前请求内容过多，超出服务器限制');
    if (s == 403) throw const ApiException(403, '当前请求被拦截，请联系管理员关闭防火墙');
    if (s < 200 || s >= 300) throw ApiException(s, '网络错误:  $s');
  }

  /// The `get` worker method (0xe68198): the text behind a backup download url. A missing backup fails with `网络错误:  404`
  /// (the device dialog turns a message containing `404` into `此设备…备份为空`).
  static Future<String> downloadBackup(String url) async {
    Response<dynamic> r;
    try {
      r = await QHttp.dio.get<dynamic>(url, options: Options(responseType: ResponseType.bytes));
    } on DioException catch (e) {
      throw ApiException(-1, '网络错误:  ${e.message ?? e.type.name}');
    }
    final s = r.statusCode ?? 0;
    if (s < 200 || s >= 300) throw ApiException(s, '网络错误:  $s');
    final data = r.data;
    return utf8.decode(data is List<int> ? data : utf8.encode('${data ?? ''}'), allowMalformed: true);
  }

  // ---------------------------------------------------------------- diagnostics

  /// Not in the original: sends the self-check results to the owner's server (`diag`) so a device can be diagnosed remotely.
  static Future<Map<String, dynamic>> diag(List<CheckResult> results) async {
    final r = _ok(await _call('diag', withAppid: true, params: {
      'app': SelfCheck.appVersion,
      'platform': Common.platform,
      'model': Common.deviceModel,
      'results': [for (final x in results) x.toJson()],
    }), '上报失败');
    return Map<String, dynamic>.from(r['data'] as Map);
  }

  // ---------------------------------------------------------------- membership

  /// `canOpenCloud`: the server-side cloud permission. False (not an exception) for non-members.
  static Future<bool> canOpenCloud() async {
    final r = await _call('canOpenCloud');
    return _code(r) == codeOk;
  }

  /// `paynew`: the purchase bridge. The owner's server accepts `paymentType: 'code'` with an activation code in `vipType`.
  static Future<void> paynew(String vipType, String paymentType) async {
    final r = _ok(await _call('paynew', params: {'vipType': vipType, 'paymentType': paymentType}), '暂不支持');
    if (r['data'] != 'ok') throw const ApiException(-1, '兑换失败');
  }

  /// Redeems an activation code, then refreshes the session (the 会员中心 page does the same with `/redeem`).
  static Future<void> redeem(String code) async {
    await paynew(code, 'code');
    await UserSession.refresh();
  }

  // ---------------------------------------------------------------- cloud sync

  /// Server etag of a list; '' when nothing is stored. Any other failure switches the bookshelf/source sync off (as the original).
  static Future<String> cloudEtag(CloudKind k) async {
    final r = await _call(k.etagCall);
    final c = _code(r);
    if (c == codeNoData) return '';
    if (c != codeOk) {
      await _failSync(r);
      return '';
    }
    return '${r['data'] ?? ''}';
  }

  /// As the original reads it (0xe6766c): '' = the cloud has newer data (or nothing stored) -> merge, '-1' = failure, any other
  /// value = the client's etag is current (the server etag).
  static Future<String> cloudUpdateUrl(CloudKind k, String etag) async {
    final r = await _call(k.updateCall, params: {'etag': etag});
    final c = _code(r);
    if (c == codeNoData) return '';
    if (c != codeOk) {
      await _failSync(r);
      return '-1';
    }
    return '${r['data'] ?? ''}';
  }

  /// The stored list as the JSON string the client uploaded; '' when nothing is stored.
  static Future<String> cloudList(CloudKind k) async {
    final r = await _call(k.listCall, params: {'st': 1});
    final c = _code(r);
    if (c == codeNoData) return '';
    _ok(r, '获取云端失败');
    return '${r['data'] ?? ''}';
  }

  static Future<void> _failSync(Map<String, dynamic> r) async {
    await UserSession.disableCloudSync();
    final msg = r['errorMsg'];
    if (msg is String && msg.isNotEmpty && msg != needLogin) Toast.show(msg, iserror: true);
  }

  /// `getItemJson`: '' when the item is not stored.
  static Future<String> getItemJson(String item) async {
    final r = await _call('getItemJson', withAppid: true, params: {'item': item});
    if (_code(r) == codeNoData) return '';
    _ok(r);
    return '${r['data'] ?? ''}';
  }

  /// `getItemMd5`: md5 of the stored item, '' when absent. Compare with the local md5 to skip a sync.
  static Future<String> getItemMd5(String item) async {
    final r = await _call('getItemMd5', withAppid: true, params: {'item': item});
    if (_code(r) == codeNoData) return '';
    _ok(r);
    return '${r['data'] ?? ''}';
  }

  /// `setItemJsonFile?tockenid=&appid=&item=&t=` with the content as the `file` part. [item] may also be one of
  /// books|rss|sources|notes|groups, which replaces that synced list.
  static Future<void> setItemJsonFile(String item, String content) async {
    final r = await QHttp.postFile(
      Common.url('setItemJsonFile'),
      {'tockenid': UserSession.tockenid, 'appid': Common.appid, 'item': item, 't': '$_now'},
      Uint8List.fromList(utf8.encode(content)),
      '$item.json',
    );
    await _checkExpired(r);
    _ok(r, '上传失败');
  }
}
