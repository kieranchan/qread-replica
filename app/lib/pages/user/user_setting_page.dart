// pages/user/user_setting_page.dart — account settings: profile, 会员中心, 登录设备, 修改密码, 退出登录.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/userapi.dart';
import '../../common/common.dart';
import '../../data/user.dart';
import '../../models/logindevice.dart';
import '../../qread/http.dart';
import '../../util/toast.dart';
import '../me_page.dart';
import 'user_edit_page.dart';

class UserSettingPage extends StatefulWidget {
  const UserSettingPage({super.key});

  @override
  State<UserSettingPage> createState() => _UserSettingPageState();
}

class _UserSettingPageState extends State<UserSettingPage> {
  Future<void> _devices() async {
    try {
      final list = await UserApi.getLoginDevices();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('登录设备'),
            content: SizedBox(
              width: double.maxFinite,
              child: list.isEmpty
                  ? const Text('暂无登录设备')
                  : ListView(shrinkWrap: true, children: [for (final d in list) _deviceTile(d, list, setS)]),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
          ),
        ),
      );
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  Widget _deviceTile(LoginDevice d, List<LoginDevice> list, StateSetter setS) {
    final me = d.appid == Common.appid; // this device: logging it out is the "退出登录" button
    return ListTile(
      title: Text(d.model.isEmpty ? d.appid : d.model),
      subtitle: Text('${d.platform} · ${DateTime.fromMillisecondsSinceEpoch(d.time)}'),
      trailing: IconButton(
        icon: const Icon(Icons.logout),
        onPressed: me
            ? null
            : () async {
                await UserApi.removeDevice(d.appid);
                setS(() => list.remove(d));
              },
      ),
    );
  }

  Future<void> _password() async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: oldC, obscureText: true, decoration: const InputDecoration(labelText: '原密码')),
          TextField(controller: newC, obscureText: true, decoration: const InputDecoration(labelText: '新密码')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await UserApi.changePassword(oldC.text, newC.text);
      Toast.show('密码已修改，请重新登录');
      await UserSession.clear();
      Get.until((r) => r.isFirst);
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  Future<void> _cleanCloud() async {
    final ok = await Get.defaultDialog<bool>(
      title: '删除确认',
      middleText: '确定要删除云端所有数据吗？',
      textConfirm: '删除',
      textCancel: '取消',
      onConfirm: () => Get.back(result: true),
      onCancel: () {},
    );
    if (ok != true) return;
    try {
      await UserApi.cleanUser();
      Toast.show('删除成功');
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: const Text('账号设置')),
        body: ListView(children: [
          ListTile(title: const Text('个人资料'), subtitle: Text('${UserSession.nickname} · ${UserSession.email}'), trailing: const Icon(Icons.chevron_right), onTap: () => Get.to(() => const UserEditPage())),
          ListTile(title: const Text('会员中心'), subtitle: Text(UserSession.isvip ? '会员 · 到期 ${UserSession.vipExpire}' : '非会员'), trailing: const Icon(Icons.chevron_right), onTap: openMemberCenter),
          ListTile(title: const Text('登录设备'), trailing: const Icon(Icons.chevron_right), onTap: _devices),
          ListTile(title: const Text('修改密码'), trailing: const Icon(Icons.chevron_right), onTap: _password),
          ListTile(title: const Text('删除云端数据'), trailing: const Icon(Icons.chevron_right), onTap: _cleanCloud),
          const Divider(),
          ListTile(
            key: const Key('logout'),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await UserApi.logout();
              Get.back();
            },
          ),
        ]),
      ),
    );
  }
}
