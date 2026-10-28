// pages/about_page.dart — 关于轻悦时光 (`AboutPage`, 20 functions): logo, name, 版本, 检查更新 (`check_update?platform=&version=&t=` →
// `{code, updateUrl, description}`; a newer build shows 更新提醒 with 暂不更新 / 立即更新), the 更新提醒 switch (prefs `updateReminder`,
// default on) and the links 用户协议 / 隐私声明 / 免责声明 (user_ys.dart).
// Version (0x10dd874 / 0x923f38, 0xe8eca8 = `PackageInfo.fromPlatform`): the page shows `版本 <PackageInfo.version>` (`加载中...` until it
// is read); the update check (0x1078878) sends `PackageInfo.buildNumber` (the 4th field) as `version`.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/common.dart';
import '../storage/storage.dart';
import '../util/toast.dart';
import 'setting/user_ys.dart';

class UpdateInfo {
  final String url;
  final String description;
  const UpdateInfo(this.url, this.description);
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

  /// Dio of the update check (tests inject one).
  static Dio? dio;

  /// Asks the server for a newer build; null when up to date. Throws on network errors.
  static Future<UpdateInfo?> checkUpdate() async {
    final d = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)));
    final r = await d.get<dynamic>(Common.url('check_update'),
        queryParameters: {'platform': Common.platform, 'version': await buildNumber(), 't': DateTime.now().millisecondsSinceEpoch},
        options: Options(validateStatus: (_) => true));
    final j = r.data;
    if (j is! Map) return null;
    final code = int.tryParse('${j['code'] ?? -1}') ?? -1;
    final url = '${j['updateUrl'] ?? ''}';
    if (code != 0 || url.isEmpty) return null;
    return UpdateInfo(url, '${j['description'] ?? ''}');
  }

  @override
  State<AboutPage> createState() => _AboutState();
}

class _AboutState extends State<AboutPage> {
  bool _checking = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    AboutPage.displayVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final u = await AboutPage.checkUpdate();
      if (!mounted) return;
      if (u == null) {
        Toast.show('已是最新版本');
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('更新提醒'),
            content: SingleChildScrollView(child: Text(u.description.isEmpty ? '发现新版本' : u.description)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('暂不更新')),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
                },
                child: const Text('立即更新'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Toast.show('检查更新失败: $e', iserror: true);
    } finally {
      if (mounted) setState(() => _checking = false);
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
          trailing: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
          onTap: _checking ? null : _check,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('更新提醒'),
          value: Storage.getBool(AboutPage.updateReminderKey, true),
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
