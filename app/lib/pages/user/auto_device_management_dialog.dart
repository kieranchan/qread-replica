// pages/user/auto_device_management_dialog.dart — the backup-device dialog (`AutoDeviceManagementDialog`; in the original
// `widget/user/auto_device_management_dialog.dart`, kept here in the account area). `isSource` false = 书架备份 devices
// (`getAutoDevice`), true = 书源备份 devices (`getAuto2Device`). Opened from 备份设置 (both kinds) and from the shelf's 备份导入
// (bookshelf kind).
//   frame 0x6e86d8 / header 0x6eb0c0: Dialog at most 70 % of the screen high, title 书架备份 / 书源备份, `管理或者查看你的…备份`
//   body 0x6e8988: 加载设备列表... / 加载失败 + 重试 / 暂无设备 + `在书架同步页面开启自动同步功能\n以添加备份设备` / the device list
//   item 0x6e985c: model (未知设备 when empty), platform, a 移除设备 button
//   remove 0x1051504: 确认移除 · `确定要从书架备份中移除 <model> 设备吗？` → removeAutoDevice / removeAuto2Device → 已移除 <model> / 移除失败：<e>
//   tap 0x1050a7c: bookshelf kind → close and open BackbookPage(appid); source kind → 请选择类型 (书源 / 订阅源) → getSources / getRss →
//   download → import; a 404 shows 此设备书源备份为空 / 此设备订阅源备份为空, other errors 操作失败: <e>
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../common/common.dart';
import '../../data/rss.dart';
import '../../data/source.dart';
import '../../models/logindevice.dart' show Autodevice;
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../search/backbook_page.dart';

class AutoDeviceManagementDialog extends StatefulWidget {
  final bool isSource;
  const AutoDeviceManagementDialog({super.key, this.isSource = false});

  static Future<void> show(BuildContext context, {bool isSource = false}) =>
      showDialog<void>(context: context, builder: (_) => AutoDeviceManagementDialog(isSource: isSource));

  /// Imports a downloaded source / RSS backup; returns the toast text. Replaceable (tests, a selection page later).
  static Future<String> Function(String text, {required bool rss}) importBackup = _import;

  static Future<String> _import(String text, {required bool rss}) async {
    final r = rss ? await RssSources.importJson(text) : await Sources.importJson(text);
    final what = rss ? '订阅源' : '书源';
    return '轻悦时光新增${r.added}条$what，更新${r.updated}条$what';
  }

  @override
  State<AutoDeviceManagementDialog> createState() => _AutoDeviceManagementDialogState();
}

class _AutoDeviceManagementDialogState extends State<AutoDeviceManagementDialog> {
  List<Autodevice>? _devices;
  bool _error = false;
  bool _busy = false;

  int get _kind => widget.isSource ? 2 : 1;
  String get _name => widget.isSource ? '书源备份' : '书架备份';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _devices = null;
      _error = false;
    });
    try {
      final d = await UserApi.getAutoDevices(_kind);
      if (mounted) setState(() => _devices = d);
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  String _model(Autodevice d) => d.model.isEmpty ? '未知设备' : d.model;

  Future<void> _remove(Autodevice d) async {
    if (!await Dialogs.confirm(context, '确认移除', '确定要从$_name中移除 ${_model(d)} 设备吗？', danger: true)) return;
    try {
      await UserApi.removeAutoDevice(_kind, d.appid);
      Toast.show('已移除 ${_model(d)}');
      await _loadDevices();
    } catch (e) {
      Toast.show('移除失败：$e', iserror: true);
    }
  }

  Future<int?> _chooseType() => showDialog<int>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('请选择类型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                FilledButton(key: const Key('adm_type_source'), onPressed: () => Navigator.of(ctx).pop(0), child: const Text('书源')),
                const SizedBox(height: 8),
                FilledButton.tonal(key: const Key('adm_type_rss'), onPressed: () => Navigator.of(ctx).pop(1), child: const Text('订阅源')),
              ]),
            ),
          ),
        ),
      );

  Future<void> _open(Autodevice d) async {
    if (!widget.isSource) {
      final nav = Navigator.of(context);
      nav.pop();
      await nav.push(MaterialPageRoute<void>(builder: (_) => BackbookPage(appid: d.appid)));
      return;
    }
    final type = await _chooseType();
    if (type == null || !mounted) return;
    final rss = type == 1;
    setState(() => _busy = true);
    try {
      final url = rss ? await UserApi.getRss(d.appid) : await UserApi.getSources(d.appid);
      final text = await UserApi.downloadBackup(url);
      Toast.show(await AutoDeviceManagementDialog.importBackup(text, rss: rss));
    } catch (e) {
      if ('$e'.contains('404')) {
        Toast.show(rss ? '此设备订阅源备份为空' : '此设备书源备份为空', iserror: true);
      } else {
        Toast.show('操作失败: $e', iserror: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _body(ColorScheme cs) {
    if (_error) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: cs.error, size: 40),
          const SizedBox(height: 8),
          const Text('加载失败'),
          const SizedBox(height: 12),
          ElevatedButton.icon(key: const Key('adm_retry'), onPressed: _loadDevices, icon: const Icon(Icons.refresh), label: const Text('重试')),
        ]),
      );
    }
    final list = _devices;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('加载设备列表...'),
        ]),
      );
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.devices_other_outlined, size: 40, color: cs.outline),
          const SizedBox(height: 8),
          const Text('暂无设备'),
          const SizedBox(height: 4),
          Text(widget.isSource ? '在书源同步页面开启自动同步功能\n以添加备份设备' : '在书架同步页面开启自动同步功能\n以添加备份设备',
              textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 13)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = list[i];
        final current = d.appid == Common.appid;
        return Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
          child: InkWell(
            key: Key('adm_device_${d.appid}'),
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : () => _open(d),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(children: [
                Icon(d.platform.toLowerCase().contains('ios') ? Icons.phone_iphone : Icons.devices, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_model(d), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(current ? '${d.platform} · 当前设备' : d.platform, style: TextStyle(fontSize: 12, color: cs.outline)),
                  ]),
                ),
                IconButton(
                  key: Key('adm_remove_${d.appid}'),
                  tooltip: '移除设备',
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  onPressed: _busy ? null : () => _remove(d),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.sizeOf(context).height * 0.7;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h, maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('管理或者查看你的$_name', style: TextStyle(fontSize: 13, color: cs.outline)),
                ]),
              ),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          Flexible(child: _body(cs)),
        ]),
      ),
    );
  }
}
