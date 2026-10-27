// pages/me_page.dart — 「我的」: account card, 会员中心 entry (opens `<base>vip?tockenid=<token>` and refreshes the account when
// the page closes), account settings, cloud settings.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common/common.dart';
import '../data/user.dart';
import 'login_page.dart';
import 'self_check_page.dart';
import 'user/cloud_setting_page.dart';
import 'user/user_setting_page.dart';
import 'web/nwebview.dart';

/// Opens the membership page exactly like the original (`vip?tockenid=` appended to the base), then refreshes the account.
Future<void> openMemberCenter() async {
  await Get.to(() => NWebviewPage(url: '${Common.apiBase}vip?tockenid=${UserSession.tockenid}', title: '会员中心'));
  await UserSession.refresh();
}

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) {
        final logged = UserSession.isLoggedIn;
        return Scaffold(
          appBar: AppBar(title: const Text('我的')),
          body: ListView(children: [
            ListTile(
              key: const Key('me_account'),
              leading: CircleAvatar(
                radius: 26,
                backgroundImage: logged && UserSession.avatarUrl.isNotEmpty ? NetworkImage(UserSession.avatarUrl) : null,
                child: logged && UserSession.avatarUrl.isNotEmpty ? null : const Icon(Icons.person),
              ),
              title: Text(logged ? UserSession.nickname : '登录同步阅读数据'),
              subtitle: logged ? Text(UserSession.vipLabel) : const Text('登录后可使用云端同步'),
              trailing: logged ? null : const Icon(Icons.chevron_right),
              onTap: logged ? () => Get.to(() => const UserSettingPage()) : () => Get.to(() => const LoginPage()),
            ),
            const Divider(height: 1),
            if (logged)
              ListTile(
                key: const Key('me_member'),
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('会员中心'),
                trailing: UserSession.isvip ? null : const Text('立即开通', style: TextStyle(color: Colors.orange)),
                onTap: openMemberCenter,
              ),
            ListTile(
              key: const Key('me_cloud'),
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('云端设置'),
              onTap: () => logged ? Get.to(() => const CloudSettingPage()) : Get.to(() => const LoginPage()),
            ),
            ListTile(
              key: const Key('me_self_check'),
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('诊断自检'),
              subtitle: const Text('检查服务器连接、会员状态与云端读写'),
              onTap: () => Get.to(() => const SelfCheckPage()),
            ),
          ]),
        );
      },
    );
  }
}
