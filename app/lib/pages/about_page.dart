// pages/about_page.dart — 关于轻悦时光 (`AboutPage`, 20 functions): logo, name, 版本, 检查更新, the 更新提醒 switch (prefs `updateReminder`,
// default on) and the links 用户协议 / 隐私声明 / 免责声明 (user_ys.dart).
// Version (0x10dd874 / 0x923f38, 0xe8eca8 = `PackageInfo.fromPlatform`): the page shows `版本 <PackageInfo.version>` (`加载中...` until it
// is read); the update check (0x1078878) sends `PackageInfo.buildNumber` (the 4th field) as `version`.
//
// Update check as the original:
//   * request 0x1078878: `<apiBase>check_update?platform=ios&version=<build number>&t=<ms>`; reply `code` 0 = a newer build exists with
//     `updateUrl` + `description` (class `UpdateMsg` of api/userapi.dart); anything else, and any error, is "no update";
//   * 检查更新 on this page (0x1078708): a progress dialog 正在检查更新... that cannot be dismissed, then 发现新版本 (更新内容: + text,
//     暂不更新 / 立即更新, 0x7a4340), 已是最新版本 / 当前应用已是最新版本，无需更新。/ 确定 (0x7a4200), or on a failure 检查更新失败 /
//     网络连接失败，请稍后重试。/ 确定 (0x7a40c0);
//   * main page start-up (0x10bcc40, from the post-frame callback 0x10bca48): when `updateReminder` is unset or "true" (0x8e9124), check
//     and show 发现新版本 only when there is an update (0x8e9194) — [AboutPage.remindOnStart].
// 立即更新 closes the dialog and opens `updateUrl` outside the app. The owner's server answers from the release set with
// `qread-admin set-update <file.json>`.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/common.dart';
import '../storage/storage.dart';
import 'setting/user_ys.dart';

/// Original class `UpdateMsg` (api/userapi.dart, 3 slots): has an update, its url, its description.
class UpdateMsg {
  final bool hasUpdate;
  final String updateUrl;
  final String description;
  const UpdateMsg(this.hasUpdate, this.updateUrl, this.description);

  static const UpdateMsg none = UpdateMsg(false, '', '');
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  /// Fallback when the platform cannot report its version (desktop tests).
  static const String version = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  /// The app's package info (tests replace it).
  static Future<PackageInfo> Function() packageInfo = PackageInfo.fromPlatform;

  /// `PackageInfo.version` for display, [version] when the platform has none.
  static Future<String> displayVersion() async {
    try {
      final v = (await packageInfo()).version;
      return v.isEmpty ? version : v;
    } catch (_) {
      return version;
    }
  }

  /// `PackageInfo.buildNumber`, what `check_update` sends as `version` (0x1078878); [version] when unavailable.
  static Future<String> buildNumber() async {
    try {
      final b = (await packageInfo()).buildNumber;
      return b.isEmpty ? version : b;
    } catch (_) {
      return version;
    }
  }
  static const String updateReminderKey = 'updateReminder';

  /// 0x8e9124: the reminder is on when `updateReminder` is unset or "true".
  static bool get reminderOn {
    final v = Storage.getString(updateReminderKey);
    return v.isEmpty || v == 'true';
  }

  /// Dio of the update check (tests inject one).
  static Dio? dio;

  /// Opens the update link (tests replace it).
  static Future<void> Function(String url) openUrl = (url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  };

  /// 0x1078878: asks the server for a newer build. Never throws: a failure is "no update", like the original.
  static Future<UpdateMsg> checkUpdate() async {
    try {
      final d = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)));
      final url = '${Common.url('check_update')}?platform=${Uri.encodeQueryComponent(Common.platform)}'
          '&version=${Uri.encodeQueryComponent(await buildNumber())}&t=${DateTime.now().millisecondsSinceEpoch}';
      final r = await d.get<dynamic>(url, options: Options(validateStatus: (_) => true));
      final j = r.data;
      if (j is! Map) return UpdateMsg.none;
      final c = j['code'];
      final code = c is num ? c.toInt() : int.tryParse('$c');
      if (code != 0) return UpdateMsg.none;
      final u = j['updateUrl'];
      final desc = j['description'];
      return UpdateMsg(true, u is String ? u : '', desc is String ? desc : '');
    } catch (_) {
      return UpdateMsg.none;
    }
  }

  /// The main page's start-up check (0x10bcc40): when the reminder is on and a newer build exists, shows 发现新版本 (0x8e9194).
  /// Call it once from the main page's first post-frame callback, without awaiting it. Returns whether the dialog was shown.
  static Future<bool> remindOnStart(BuildContext context) async {
    if (!reminderOn) return false;
    final msg = await checkUpdate();
    if (!msg.hasUpdate || !context.mounted) return false;
    showDialog<void>(context: context, builder: (ctx) => updateDialog(ctx, msg));
    return true;
  }

  /// 发现新版本 with 更新内容: (0x8e9194 on the main page, 0x7a4340 here): 暂不更新 closes, 立即更新 closes and opens the link.
  static Widget updateDialog(BuildContext ctx, UpdateMsg msg) => AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('更新内容:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(msg.description),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('暂不更新')),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openUrl(msg.updateUrl);
            },
            child: const Text('立即更新'),
          ),
        ],
      );

  @override
  State<AboutPage> createState() => _AboutState();
}

class _AboutState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    AboutPage.displayVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  static Widget _plain(BuildContext ctx, String title, String text) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('确定'))],
      );

  /// 0x1078708.
  Future<void> _check() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('正在检查更新...'),
        ]),
      ),
    );
    try {
      final msg = await AboutPage.checkUpdate();
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => msg.hasUpdate ? AboutPage.updateDialog(ctx, msg) : _plain(ctx, '已是最新版本', '当前应用已是最新版本，无需更新。'),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(context: context, builder: (ctx) => _plain(ctx, '检查更新失败', '网络连接失败，请稍后重试。'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于轻悦时光')),
      body: ListView(children: [
        const SizedBox(height: 32),
        Center(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('lib/assets/images/logo.png', width: 88, height: 88))),
        const SizedBox(height: 12),
        Center(child: Text('轻悦时光', style: Theme.of(context).textTheme.titleLarge)),
        Center(child: Text('版本 ${_version.isEmpty ? '加载中...' : _version}', key: const Key('about_version'), style: TextStyle(color: cs.outline))),
        const SizedBox(height: 24),
        ListTile(
          key: const Key('about_check'),
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('检查更新'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _check,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('更新提醒'),
          value: AboutPage.reminderOn,
          onChanged: (v) async {
            await Storage.setBool(AboutPage.updateReminderKey, v);
            setState(() {});
          },
        ),
        const Divider(),
        ListTile(leading: const Icon(Icons.description_outlined), title: const Text('用户协议'), onTap: () => Get.to(() => const UserAgreementPage(title: '用户协议'))),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('隐私声明'), onTap: () => Get.to(() => const UserAgreementPage(title: '隐私声明'))),
        ListTile(leading: const Icon(Icons.gavel_outlined), title: const Text('免责声明'), onTap: () => Get.to(() => const UserAgreementPage(title: '免责声明'))),
        const SizedBox(height: 24),
        Center(child: Text('个人自用复刻版，与原应用无关', style: TextStyle(fontSize: 12, color: cs.outline))),
        const SizedBox(height: 24),
      ]),
    );
  }
}
