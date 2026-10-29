// pages/tts/tts_setting.dart — 朗读引擎 (`TTsSetting`, state `_ReplaceRuleSettingState`, 235 functions). Structure of the original:
//   * engine list (data/tts.dart): 系统默认 first (cannot be deleted), then the user's engines; tap = 试听 with
//     `君不见黄河之水天上来，奔流到海不复回。`; menu 编辑 / 删除 (`删除确认`) / 置顶 / 置底 (`确定要把《x》置顶吗？` → `置顶成功`);
//     multi-select (全选 (n) / 反选) for bulk delete; import of Legado HttpTTS JSON (`请选择您想要导入的朗读引擎文件`, `导入失败:` /
//     `选择文件失败:`).
//   * 新增 → `请选择新建引擎类型` dialog (0x61bf4c: 普通引擎 = 1 / 多角色引擎 = 0, footer `注：多角色引擎是基于ai的功能，需要在阅读设置里
//     配置ai大模型。`) plus the engine kinds of 0x606390: 火山引擎 (字节跳动 · 21 款音色), MiMo引擎 (小米 MiMo · 预置/克隆/音色设计),
//     本地引擎 (sherpa-onnx 离线模型 · 无需联网); 大声朗读 (the Edge voice) is not offered (Edge client token, porting rule 4).
//     Volcano / MiMo engines are pages with the user's own credentials (pages/tts/vendor_engines.dart).
//   * 本地引擎 opens the model manager sheet (pages/tts/local/local_engine_sheet.dart, 0x606d14): import / download sherpa-onnx model
//     packages, voices → page engines, clone engines, per-model synthesis settings. As in the original the sheet has no member check
//     (it only shows `本地引擎仅 VIP 可用`); the gate is in synthesis (util/audio/tts_controller.dart). 试听 passes the original's debug
//     callback (0xfe19f8 → 0xe90260), which lets non-members hear local engines here.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/tts.dart';
import '../../models/httptts.dart';
import '../../storage/setting.dart';
import '../../theme/widgets.dart';
import '../../util/audio/tts_controller.dart';
import '../../util/toast.dart';
import '../../util/audio/local/local_tts_manager.dart';
import 'local/local_engine_sheet.dart';
import 'multi_role_edit.dart';
import 'tts_edit.dart';
import 'tts_help.dart';
import 'vendor_engines.dart';

class TTsSetting extends StatefulWidget {
  const TTsSetting({super.key});

  static const String sample = '君不见黄河之水天上来，奔流到海不复回。';
  static const String localGate = '本地引擎仅 VIP 可用';


  @override
  State<TTsSetting> createState() => _ReplaceRuleSettingState();
}

class _ReplaceRuleSettingState extends State<TTsSetting> {
  final Set<String> _selected = {};
  bool _selecting = false;
  String _playing = '';

  @override
  void initState() {
    super.initState();
    TTSData.load().then((_) {
      if (mounted) setState(() {});
    });
    LocalTtsManager.load().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    TtsController.stop();
    super.dispose();
  }

  List<HttpTts> get _engines => TTSData.engines;

  Future<void> _audition(HttpTts e) async {
    if (_playing == e.id) {
      await TtsController.stop();
      setState(() => _playing = '');
      return;
    }
    setState(() => _playing = e.id);
    try {
      await TtsController.speak(e, TTsSetting.sample, debug: (m) => debugPrint(m));
    } catch (err) {
      Toast.show('$err', iserror: true);
    } finally {
      if (mounted) setState(() => _playing = '');
    }
  }

  Future<void> _newEngine() async {
    final kind = await showDialog<TtsKind>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('请选择新建引擎类型', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final k in const [
              (TtsKind.http, '普通引擎', '导入或编写网页 / HTTP 朗读引擎'),
              (TtsKind.multiRole, '多角色引擎', '多角色引擎，按角色分配音色'),
              (TtsKind.volcano, '火山引擎', '字节跳动 · 21 款音色'),
              (TtsKind.mimo, 'MiMo引擎', '小米 MiMo · 预置/克隆/音色设计'),
              (TtsKind.local, '本地引擎', 'sherpa-onnx 离线模型 · 无需联网'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  key: Key('tts_new_${k.$1.name}'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => Navigator.of(ctx).pop(k.$1),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(k.$3, style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            Text('注：多角色引擎是基于ai的功能，需要在阅读设置里配置ai大模型。', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          ]),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    switch (kind) {
      case TtsKind.http:
        await Get.to(() => const EditTts());
      case TtsKind.multiRole:
        if (Setting.roleAnalysisModel == null) {
          Toast.show('多角色引擎需要ai支持，请先配置ai接口', iserror: true);
          return;
        }
        await Get.to(() => const MultiRoleEdit());
      case TtsKind.volcano:
        await VendorEngines.volcano(context);
      case TtsKind.mimo:
        await VendorEngines.mimo(context);
      case TtsKind.local:
        await LocalEngineSheet.show(context);
      case TtsKind.edge:
        Toast.show(TtsController.edgeMissing);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit(HttpTts e) async {
    switch (TtsKind.of(e)) {
      case TtsKind.http:
        await Get.to(() => EditTts(engine: e));
      case TtsKind.multiRole:
        await Get.to(() => MultiRoleEdit(engine: e));
      case TtsKind.volcano:
        if (TTSData.pageOf(e).isEmpty) return VendorEngines.volcanoCredentials(context);
        await Get.to(() => EditTts(engine: e));
      case TtsKind.mimo:
        if (TTSData.pageOf(e).isEmpty) return VendorEngines.mimoKey(context);
        await Get.to(() => EditTts(engine: e));
      case TtsKind.local:
      case TtsKind.edge:
        await Get.to(() => EditTts(engine: e));
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(List<String> ids) async {
    if (ids.isEmpty) return;
    if (!await Dialogs.confirm(context, '删除确认', ids.length == 1 ? '确定要删除该朗读引擎吗？' : '确定要删除这些朗读引擎吗？', danger: true)) return;
    for (final id in ids) {
      try {
        await Tts.delete(id);
      } catch (e) {
        Toast.show('删除失败: $e', iserror: true);
      }
    }
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _move(HttpTts e, {required bool top}) async {
    if (!await Dialogs.confirm(context, top ? '置顶确认' : '置底确认', '确定要把《${e.name}》${top ? '置顶' : '置底'}吗？')) return;
    try {
      await TTSData.store.run((list) {
        list.removeWhere((x) => x.id == e.id && x.bookurl.isEmpty);
        if (top) {
          list.insert(0, e);
        } else {
          list.add(e);
        }
      });
      Toast.show(top ? '置顶成功' : '置底成功');
    } catch (err) {
      Toast.show('${top ? '置顶' : '置底'}失败: $err', iserror: true);
    }
    setState(() {});
  }

  /// 置顶所有 / 置底所有 of the selection (0xfdf838 / 0xfdf408: 置顶确认 `确定要置顶这些引擎吗？` → 置顶成功); the selected engines keep
  /// their relative order.
  Future<void> _moveMany(List<String> ids, {required bool top}) async {
    if (ids.isEmpty) return;
    if (!await Dialogs.confirm(context, top ? '置顶确认' : '置底确认', top ? '确定要置顶这些引擎吗？' : '确定要置底这些引擎吗？')) return;
    try {
      await TTSData.store.run((list) {
        final picked = [for (final e in list) if (ids.contains(e.id) && e.bookurl.isEmpty) e];
        list.removeWhere(picked.contains);
        if (top) {
          list.insertAll(0, picked);
        } else {
          list.addAll(picked);
        }
      });
      Toast.show(top ? '置顶成功' : '置底成功');
    } catch (err) {
      Toast.show('${top ? '置顶' : '置底'}失败: $err', iserror: true);
    }
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _import() async {
    try {
      final f = await DeviceIo.pickFile(extensions: const ['json', 'txt']);
      if (f == null) return;
      final n = await Tts.importJson(await f.readAsString());
      Toast.show('导入成功: $n');
    } on FormatException catch (e) {
      Toast.show('导入失败:${e.message}', iserror: true);
    } catch (e) {
      Toast.show('导入失败:$e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Widget _tile(HttpTts e) {
    final cs = Theme.of(context).colorScheme;
    final system = TtsController.isSystem(e);
    final kind = system ? '系统默认' : TtsKind.of(e).label;
    return ListTile(
      key: Key('tts_${e.id}'),
      leading: _selecting && !system
          ? Checkbox(value: _selected.contains(e.id), onChanged: (v) => setState(() => v == true ? _selected.add(e.id) : _selected.remove(e.id)))
          : IconButton(
              tooltip: '试听',
              icon: Icon(_playing == e.id ? Icons.stop_circle_outlined : Icons.play_circle_outline, color: cs.primary),
              onPressed: () => _audition(e),
            ),
      title: Text(e.name),
      subtitle: Text(kind, style: TextStyle(fontSize: 12, color: cs.outline)),
      onLongPress: system
          ? null
          : () => setState(() {
                _selecting = true;
                _selected.add(e.id);
              }),
      onTap: _selecting && !system ? () => setState(() => _selected.contains(e.id) ? _selected.remove(e.id) : _selected.add(e.id)) : () => _audition(e),
      trailing: system
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(e);
                  case 'top':
                    _move(e, top: true);
                  case 'bottom':
                    _move(e, top: false);
                  case 'delete':
                    _delete([e.id]);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'top', child: Text('置顶')),
                PopupMenuItem(value: 'bottom', child: Text('置底')),
                PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
              ],
            ),
    );
  }

  Widget _localSection() {
    final cs = Theme.of(context).colorScheme;
    final n = LocalTtsManager.models.length;
    return SectionCard(title: '本地引擎', children: [
      ListTile(
        key: const Key('tts_local'),
        leading: const Icon(Icons.memory_outlined),
        title: const Text('sherpa-onnx 离线模型 · 无需联网'),
        subtitle: Text(n == 0 ? '尚未导入模型包' : '已导入 $n 个模型', style: TextStyle(fontSize: 12, color: cs.outline)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await LocalEngineSheet.show(context);
          if (mounted) setState(() {});
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final engines = _engines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('朗读引擎'),
        actions: [
          if (_selecting) ...[
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == engines.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(engines.map((e) => e.id));
                }
              }),
              child: Text('全选 (${_selected.length})'),
            ),
            TextButton(
              onPressed: () => setState(() {
                final inv = engines.map((e) => e.id).toSet().difference(_selected);
                _selected
                  ..clear()
                  ..addAll(inv);
              }),
              child: const Text('反选'),
            ),
            IconButton(tooltip: '置顶所有', icon: const Icon(Icons.vertical_align_top), onPressed: () => _moveMany(_selected.toList(), top: true)),
            IconButton(tooltip: '置底所有', icon: const Icon(Icons.vertical_align_bottom), onPressed: () => _moveMany(_selected.toList(), top: false)),
            IconButton(tooltip: '批量删除', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(_selected.toList())),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selecting = false)),
          ] else ...[
            IconButton(key: const Key('tts_add'), tooltip: '新增', icon: const Icon(Icons.add), onPressed: _newEngine),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) {
                if (v == 'import') _import();
                if (v == 'help') Get.to(() => const TTSHelpPage());
                if (v == 'export') _export();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'import', child: Text('本地导入')),
                PopupMenuItem(value: 'export', child: Text('导出')),
                PopupMenuItem(value: 'help', child: Text('帮助')),
              ],
            ),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SectionCard(children: [
          _tile(TTSData.defaultEngine),
          for (final e in engines) _tile(e),
        ]),
        _localSection(),
      ]),
    );
  }

  Future<void> _export() async {
    final list = [for (final e in _engines) if (TtsKind.of(e) != TtsKind.multiRole) Tts.toOriginal(e)];
    if (list.isEmpty) return Toast.show('您选择的引擎为空!(多角色引擎无法导出)');
    final text = const JsonEncoder.withIndent('  ').convert(list);
    await Get.to(() => TTSHelpPage(title: '导出', code: text));
  }
}
