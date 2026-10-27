// pages/user/backup_setting_page.dart — 备份设置 (`BackupSettingPage`, 14 functions): 书架备份 (`autoSyncEnabled`, `当网络连接时自动备份
// 书架`; refused while 云端书架 is on: `书架备份无法和云端书架同时打开`), 书源备份 (`auto2SyncEnabled`, member-only `书源备份是会员功能。`;
// refused while 云端书源 is on), 立即备份 (`备份中...`, `上次备份：…`, `上次书源备份：…`, `上次订阅源备份：…`), 进度同步
// (`autoSyncProgressEnabled`, `当网络连接时每分钟会备份一次进度，进度最多保存7天`, `是否立即同步一次？`, `自动同步失败: …`) and the backup
// devices of the account (getAutoDevice / getAuto2Device; free accounts keep at most 2).
// TODO(asm 0xf223ac / 0xf226c4): switching a backup on also registers the device (`openAuto` / `newopenAuto2`); those calls are not in
// UserApi yet, so the switch is local and [backupNow] is the hook the data area wires to its upload.
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../data/user.dart';
import '../../models/logindevice.dart' show Autodevice;
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';

class BackupSettingPage extends StatefulWidget {
  const BackupSettingPage({super.key});

  /// Runs one backup of the bookshelf ([sources] false) or of the sources and RSS ([sources] true).
  static Future<void> Function({required bool sources}) backupNow = ({required bool sources}) async {
    throw UnsupportedError('当前版本尚未接入云端备份上传');
  };

  @override
  State<BackupSettingPage> createState() => _BackupSettingPageState();
}

class _BackupSettingPageState extends State<BackupSettingPage> {
  bool _busy = false;
  List<Autodevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (!UserSession.isLoggedIn) return;
    try {
      final d = await UserApi.getAutoDevices(1);
      if (mounted) setState(() => _devices = d);
    } catch (_) {}
  }

  Future<void> _toggle(String key, bool v) async {
    if (v) {
      if (key == PrefKeys.autoSyncEnabled && UserSession.cloudbookself) return Toast.show('书架备份无法和云端书架同时打开', iserror: true);
      if (key == PrefKeys.auto2SyncEnabled) {
        if (!Vip.require('书源备份是会员功能。')) return;
        if (UserSession.cloudsource) return Toast.show('书源备份无法和云端书源同时打开', iserror: true);
      }
    }
    await UserSession.setSwitch(key, v);
    if (v && key == PrefKeys.autoSyncProgressEnabled && mounted) {
      if (await Dialogs.confirm(context, '操作确认', '是否立即同步一次？')) await _now(false);
    }
  }

  Future<void> _now(bool sources) async {
    setState(() => _busy = true);
    try {
      await BackupSettingPage.backupNow(sources: sources);
      await Storage.setString(sources ? PrefKeys.lastSyncTime2 : PrefKeys.lastSyncTime, DateTime.now().toString().substring(0, 19));
    } catch (e) {
      Toast.show('自动同步失败: $e', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String last(String k) => Storage.getString(k).isEmpty ? '-' : Storage.getString(k);
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: const Text('备份设置')),
        body: ListView(children: [
          SectionCard(title: '自动备份', children: [
            SwitchListTile(
              key: const Key('bs_books'),
              title: const Text('书架备份'),
              subtitle: const Text('当网络连接时自动备份书架'),
              value: UserSession.autoSyncEnabled,
              onChanged: (v) => _toggle(PrefKeys.autoSyncEnabled, v),
            ),
            SwitchListTile(
              key: const Key('bs_sources'),
              title: const Text('书源备份'),
              subtitle: const Text('当网络连接时自动备份书源'),
              value: UserSession.auto2SyncEnabled,
              onChanged: (v) => _toggle(PrefKeys.auto2SyncEnabled, v),
            ),
            ListTile(
              title: const Text('立即备份'),
              subtitle: Text('上次备份：${last(PrefKeys.lastSyncTime)}\n上次书源备份：${last(PrefKeys.lastSyncTime2)}\n上次订阅源备份：${last(PrefKeys.lastSyncTimer3)}'),
              isThreeLine: true,
              trailing: _busy ? const Text('备份中...') : const Icon(Icons.backup_outlined),
              onTap: _busy ? null : () => _now(false),
            ),
          ]),
          SectionCard(title: '进度同步', children: [
            SwitchListTile(
              title: const Text('自动同步'),
              subtitle: const Text('当网络连接时每分钟会备份一次进度，进度最多保存7天'),
              value: UserSession.autoSyncProgressEnabled,
              onChanged: (v) => _toggle(PrefKeys.autoSyncProgressEnabled, v),
            ),
          ]),
          if (_devices.isNotEmpty)
            SectionCard(title: '备份设备', children: [
              for (final d in _devices)
                ListTile(
                  title: Text(d.model.isEmpty ? '未知设备' : d.model),
                  subtitle: Text(d.platform),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: () async {
                      try {
                        await UserApi.removeAutoDevice(1, d.appid);
                        Toast.show('移除成功');
                        await _loadDevices();
                      } catch (e) {
                        Toast.show('移除失败', iserror: true);
                      }
                    },
                  ),
                ),
            ]),
        ]),
      ),
    );
  }
}
