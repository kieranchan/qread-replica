// pages/user/user_setting_page.dart — account settings (`UserSettingPage`; strings 会员中心 · 永久 · 账号与安全 · 安全与隐私 · 云端设置 ·
// 备份设置 · 已成功登出): profile header (→ UserEditPage), 会员中心 (vip text; `永久` members see no renewal), 账号与安全 section with
// 安全与隐私 (password, devices, account deletion), 云端设置, 备份设置, and 退出登录 (`已成功登出`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/userapi.dart';
import '../../data/user.dart';
import '../../util/toast.dart';
import '../me_page.dart';
import 'backup_setting_page.dart';
import 'cloud_setting_page.dart';
import 'security_privacy_page.dart';
import 'user_edit_page.dart';

class UserSettingPage extends StatefulWidget {
  const UserSettingPage({super.key});

  @override
  State<UserSettingPage> createState() => _UserSettingPageState();
}

class _UserSettingPageState extends State<UserSettingPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: const Text('账号设置')),
        body: ListView(children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: UserSession.avatarUrl.isNotEmpty ? NetworkImage(UserSession.avatarUrl) : const AssetImage('lib/assets/images/me.png') as ImageProvider,
            ),
            title: Text(UserSession.nickname),
            subtitle: Text(UserSession.email),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const UserEditPage()),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('会员中心'),
            subtitle: Text(UserSession.vipLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: openMemberCenter,
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('账号与安全', style: TextStyle(color: cs.primary))),
          ListTile(leading: const Icon(Icons.security_outlined), title: const Text('安全与隐私'), trailing: const Icon(Icons.chevron_right), onTap: () => Get.to(() => const SecurityPrivacyPage())),
          ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('云端设置'), trailing: const Icon(Icons.chevron_right), onTap: () => Get.to(() => const CloudSettingPage())),
          ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('备份设置'), trailing: const Icon(Icons.chevron_right), onTap: () => Get.to(() => const BackupSettingPage())),
          const Divider(),
          ListTile(
            key: const Key('logout'),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await UserApi.logout();
              Toast.show('已成功登出');
              Get.back();
            },
          ),
        ]),
      ),
    );
  }
}
