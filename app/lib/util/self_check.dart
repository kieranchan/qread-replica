// util/self_check.dart — the checks behind the 「诊断自检」 page. Each one is independent and never throws; the list can be sent to
// the server (`UserApi.diag`) so a failing device can be diagnosed from the server side without touching the phone.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../api/userapi.dart';
import '../common/common.dart';
import '../data/user.dart';
import '../qread/http.dart';

class CheckResult {
  final String name;
  final bool ok;
  final String detail;
  const CheckResult(this.name, this.ok, this.detail);

  Map<String, dynamic> toJson() => {'name': name, 'ok': ok, 'detail': detail};
}

abstract class SelfCheck {
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'newread 1.0.0+1');

  static Future<CheckResult> _run(String name, Future<String> Function() body) async {
    try {
      return CheckResult(name, true, await body());
    } catch (e) {
      return CheckResult(name, false, '$e');
    }
  }

  /// Runs every check that applies to the current state (signed out: only connectivity).
  static Future<List<CheckResult>> run() async {
    final out = <CheckResult>[];
    out.add(await _run('服务器连通', () async {
      final r = await QHttp.get('${Common.apiBase}healthz');
      if (r['ok'] != true) throw '服务器返回异常';
      return '${Common.apiBase} · 用户数 ${r['users']}';
    }));
    out.add(CheckResult('设备信息', true, '${Common.platform} · ${Common.deviceModel} · appid ${Common.appid.isEmpty ? '(空)' : Common.appid.substring(0, Common.appid.length.clamp(0, 8))}…'));
    if (!UserSession.isLoggedIn || UserSession.tockenid.isEmpty) {
      out.add(const CheckResult('登录状态', true, '未登录（只做连通检查）'));
      return out;
    }
    out.add(await _run('账号信息 getUserInfo', () async {
      final u = await UserApi.getUserInfo();
      if (u == null) throw '获取失败或令牌已过期';
      if (u.isvip != UserSession.isvip) throw '本地会员状态 ${UserSession.isvip} 与服务器 ${u.isvip} 不一致';
      return '${u.username} · ${u.isvip ? '会员 ${u.vip}' : '非会员'}';
    }));
    out.add(await _run('会员门槛 canOpenCloud', () async {
      final can = await UserApi.canOpenCloud();
      if (can != UserSession.isvip) throw '云端权限 $can 与会员状态 ${UserSession.isvip} 不一致';
      return can ? '会员：云端已开放' : '非会员：云端关闭（符合预期）';
    }));
    out.add(await _run('登录设备列表', () async {
      final d = await UserApi.getLoginDevices();
      if (!d.any((x) => x.appid == Common.appid)) throw '列表里没有本机（appid ${Common.appid}）';
      return '${d.length} 台设备，含本机';
    }));
    if (UserSession.isvip) {
      out.add(await _run('云端读写 selfcheck', () async {
        final payload = '{"selfcheck":${DateTime.now().millisecondsSinceEpoch}}';
        await UserApi.setItemJsonFile('selfcheck', payload);
        final md5Remote = await UserApi.getItemMd5('selfcheck');
        final md5Local = md5.convert(utf8.encode(payload)).toString();
        if (md5Remote != md5Local) throw 'md5 不一致：$md5Remote ≠ $md5Local';
        final back = await UserApi.getItemJson('selfcheck');
        if (back != payload) throw '读回内容不一致';
        return '写入 / md5 / 读回 一致';
      }));
    } else {
      out.add(const CheckResult('云端读写', true, '非会员，已跳过'));
    }
    return out;
  }
}
