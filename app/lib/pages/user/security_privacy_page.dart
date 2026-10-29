// pages/user/security_privacy_page.dart — 安全与隐私 (`SecurityPrivacyPage`, 17 functions): 修改密码 (`定期修改密码以保护账户安全`,
// `为了账户安全，请定期更换密码，不要与其他网站使用相同的密码`), 登录设备 (`管理所有设备`: 当前设备 / 在线 / `未知设备` / `未知平台`,
// remove other devices; `获取设备列表失败: …`) and 注销账户 (`注销后所有数据将被删除，此操作不可撤销` → 警告 → 最终确认
// `为了确认您的操作，请输入 '注销' 二字` → `cleanuser` + logout → `账户注销成功` / `注销失败: …`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/userapi.dart';
import '../../common/common.dart';
import '../../data/user.dart';
import '../../models/logindevice.dart';
import '../../qread/http.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import 'account_validators.dart';

class SecurityPrivacyPage extends StatefulWidget {
  const SecurityPrivacyPage({super.key});

  @override
  State<SecurityPrivacyPage> createState() => _SecurityPrivacyPageState();
}

class _SecurityPrivacyPageState extends State<SecurityPrivacyPage> {
  Future<void> _password() async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final againC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('为了账户安全，请定期更换密码，不要与其他网站使用相同的密码', style: TextStyle(fontSize: 12)),
          TextField(controller: oldC, obscureText: true, decoration: const InputDecoration(labelText: '当前密码', hintText: '请输入当前密码')),
          TextField(controller: newC, obscureText: true, decoration: const InputDecoration(labelText: '新密码', hintText: '请输入新密码')),
          TextField(controller: againC, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', hintText: '请再次输入新密码')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确认')),
        ],
      ),
    );
    if (ok != true) return;
    // 0x880a58 / 0x88091c: the original's checks
    final err = AccountValidators.password(oldC.text, empty: '请输入当前密码') ??
        AccountValidators.newPassword(oldC.text, newC.text) ??
        AccountValidators.confirm(newC.text, againC.text, empty: '请再次输入新密码');
    if (err != null) return Toast.show(err, iserror: true);
    try {
      await UserApi.changePassword(oldC.text, newC.text);
      Toast.show('密码修改成功，请重新登录');
      await UserSession.clear();
      Get.until((r) => r.isFirst);
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  Future<void> _devices() async {
    List<LoginDevice> list;
    try {
      list = await UserApi.getLoginDevices();
    } catch (e) {
      Toast.show('获取设备列表失败: $e', iserror: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('登录设备'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final d in list)
                ListTile(
                  title: Text(d.model.isEmpty ? '未知设备' : d.model),
                  subtitle: Text('${d.platform.isEmpty ? '未知平台' : d.platform} · ${d.appid == Common.appid ? '当前设备' : DateTime.fromMillisecondsSinceEpoch(d.time).toString().substring(0, 16)}'),
                  trailing: d.appid == Common.appid
                      ? const Text('在线')
                      : IconButton(
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            if (!await Dialogs.confirm(ctx, '确认移除设备', '确定要移除设备 "${d.model}" 吗？')) return;
                            try {
                              await UserApi.removeDevice(d.appid);
                              setS(() => list.remove(d));
                              Toast.show('设备移除成功');
                            } catch (e) {
                              Toast.show('移除设备失败: $e', iserror: true);
                            }
                          },
                        ),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
        ),
      ),
    );
  }

  Future<void> _cancelAccount() async {
    if (!await Dialogs.confirm(context, '警告', '注销后所有数据将被删除，此操作不可撤销', danger: true)) return;
    if (!mounted) return;
    final text = await Dialogs.input(context, '最终确认', hint: "请输入 '注销'");
    if (text?.trim() != '注销') return;
    try {
      await UserApi.cleanUser();
      await UserApi.logout();
      Toast.show('账户注销成功');
      Get.until((r) => r.isFirst);
    } catch (e) {
      Toast.show('注销失败: $e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全与隐私')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.lock_outline), title: const Text('修改密码'), subtitle: const Text('定期修改密码以保护账户安全'), onTap: _password),
        ListTile(key: const Key('sp_devices'), leading: const Icon(Icons.devices_outlined), title: const Text('登录设备'), subtitle: const Text('管理所有设备'), onTap: _devices),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.person_off_outlined, color: Colors.red),
          title: const Text('注销账户', style: TextStyle(color: Colors.red)),
          subtitle: const Text('注销后所有数据将被删除，此操作不可撤销'),
          onTap: _cancelAccount,
        ),
      ]),
    );
  }
}
