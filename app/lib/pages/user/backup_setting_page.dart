// pages/user/backup_setting_page.dart — 备份设置 (`BackupSettingPage`, 14 functions; build 0x6d87a8). Three cards:
//   书架备份: 自动备份 (`autoSyncEnabled`, `当网络连接时自动备份书架`; 0x10482a4: refused while 云端书架 is on `书架备份无法和云端书架同时打开`,
//            otherwise `openAuto` registers the device, the switch is persisted and `是否立即同步一次？` offers a first upload; failures
//            `自动同步失败: <e>`), 立即备份 (`_performSync` 0x1048068, `备份中...`), `上次备份：<lastSyncTime>` and the note on the free limit.
//   书源备份: member feature (`书源备份是会员功能。`), same flow with `newopenAuto2` (0x1047e48, conflict with 云端书源), 立即备份
//            (`_performSync2` 0x1047b98), `上次书源备份：…\n上次订阅源备份：…`.
//   进度同步: 自动同步 (`autoSyncProgressEnabled`, 0x1047aec: just the switch), `当网络连接时每分钟会备份一次进度，进度最多保存7天`.
// Below: the two device lists (AutoDeviceManagementDialog false / true, 0x6dafd4 / 0x6daf2c).
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../data/cloud/auto_backup.dart';
import '../../data/user.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';
import 'auto_device_management_dialog.dart';

class BackupSettingPage extends StatefulWidget {
  const BackupSettingPage({super.key});

  static const String freeNote = '非会员最多只能备份 2 个设备，超出后请在书架备份中删除即可。书架备份和云端书架无法同时开启。';

  @override
  State<BackupSettingPage> createState() => _BackupSettingPageState();
}

class _BackupSettingPageState extends State<BackupSettingPage> {
  bool _busyBooks = false;
  bool _busySources = false;
  bool _opening = false;

  /// 0x10482a4: 书架备份 on / off.
  Future<void> _toggleBooks(bool v) async {
    if (!v) {
      await UserSession.setSwitch(PrefKeys.autoSyncEnabled, false);
      if (mounted) setState(() {});
      return;
    }
    if (UserSession.cloudbookself) return Toast.show('书架备份无法和云端书架同时打开');
    setState(() => _opening = true);
    try {
      await UserApi.openAuto();
      await UserSession.setSwitch(PrefKeys.autoSyncEnabled, true);
      if (mounted) setState(() => _opening = false);
      if (mounted && await Dialogs.confirm(context, '操作确认', '是否立即同步一次？')) await _sync(false);
    } catch (e) {
      if (mounted) setState(() => _opening = false);
      Toast.show('自动同步失败: $e', iserror: true);
    }
  }

  /// 0x6db064 → 0x1047e48: 书源备份 on / off (member feature).
  Future<void> _toggleSources(bool v) async {
    if (!v) {
      await UserSession.setSwitch(PrefKeys.auto2SyncEnabled, false);
      if (mounted) setState(() {});
      return;
    }
    if (!Vip.require('书源备份是会员功能。')) return;
    if (UserSession.cloudsource) return Toast.show('书源备份无法和云端书源同时打开');
    setState(() => _opening = true);
    try {
      await UserApi.newopenAuto2();
      await UserSession.setSwitch(PrefKeys.auto2SyncEnabled, true);
      if (mounted) setState(() => _opening = false);
      if (mounted && await Dialogs.confirm(context, '操作确认', '是否立即同步一次？')) await _sync(true);
    } catch (e) {
      if (mounted) setState(() => _opening = false);
      Toast.show('自动同步失败: $e', iserror: true);
    }
  }

  Future<void> _sync(bool sources) async {
    setState(() => sources ? _busySources = true : _busyBooks = true);
    try {
      await (sources ? AutoBackup.performSync2() : AutoBackup.performSync());
    } finally {
      if (mounted) setState(() => sources ? _busySources = false : _busyBooks = false);
    }
  }

  Widget _card(BuildContext context, String title, List<Widget> children, {Widget? badge}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.primary),
                    ),
                    if (badge != null) ...[const SizedBox(width: 6), badge],
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _nowButton(String key, bool busy, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        key: Key(key),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cloud_upload_outlined, size: 18),
        label: Text(busy ? '备份中...' : '立即备份'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String last(String k) => Storage.getString(k);
    final small = TextStyle(fontSize: 12, color: cs.outline);
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: const Text('备份设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_opening) const LinearProgressIndicator(),
            _card(context, '书架备份', [
              SwitchListTile(
                key: const Key('bs_books'),
                title: const Text('自动备份'),
                subtitle: const Text('当网络连接时自动备份书架'),
                value: UserSession.autoSyncEnabled,
                onChanged: _opening ? null : _toggleBooks,
              ),
              _nowButton('bs_books_now', _busyBooks, () => _sync(false)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('上次备份：${last(PrefKeys.lastSyncTime)}', style: small),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(BackupSettingPage.freeNote, style: small),
              ),
            ]),
            _card(
              context,
              '书源备份',
              badge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFE6B450), borderRadius: BorderRadius.circular(6)),
                child: const Text(
                  'VIP',
                  style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              [
                SwitchListTile(
                  key: const Key('bs_sources'),
                  title: const Text('自动备份'),
                  subtitle: const Text('当网络连接时自动备份书源'),
                  value: UserSession.auto2SyncEnabled,
                  onChanged: _opening ? null : _toggleSources,
                ),
                _nowButton('bs_sources_now', _busySources, () => _sync(true)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('上次书源备份：${last(PrefKeys.lastSyncTime2)}\n上次订阅源备份：${last(PrefKeys.lastSyncTimer3)}', style: small),
                ),
                if (!UserSession.isvip)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text('书源备份是会员功能。', style: small),
                  ),
              ],
            ),
            _card(context, '进度同步', [
              SwitchListTile(
                key: const Key('bs_progress'),
                title: const Text('自动同步'),
                subtitle: const Text('当网络连接时每分钟会备份一次进度，进度最多保存7天'),
                value: UserSession.autoSyncProgressEnabled,
                onChanged: (v) async {
                  await UserSession.setSwitch(PrefKeys.autoSyncProgressEnabled, v);
                  if (mounted) setState(() {});
                },
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('bs_devices_books'),
                      onPressed: () => AutoDeviceManagementDialog.show(context, isSource: false),
                      child: const Text('书架备份'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('bs_devices_sources'),
                      onPressed: () => AutoDeviceManagementDialog.show(context, isSource: true),
                      child: const Text('书源备份'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
