// pages/tts/local/local_engine_sheet.dart — 本地引擎 · 模型管理, the bottom sheet the 本地引擎 entry of 朗读引擎 opens (original
// tts_setting.dart: sheet 0x606d14 = MyDraggableScrollableSheet 0.6 / 0.4 / 0.9, body 0x606e08, header 0x60c904, model tile 0x6074d8,
// voices 0x6087f4 / 0x60918c, 命名朗读引擎 0x609fd4, 克隆音色 0x60ac14, 合成设置 0x60b804, 下载模型 0xfe860c, 删除模型 0x6083f8).
//   header: close, `本地引擎 · 模型管理`, `下载模型` (down.json), `导入模型包` (file picker); narrow screens stack the buttons
//   body: `尚未导入模型包\n\n点右上角「导入模型包」选择 zip 模型文件` or the models: name, `<n> 款音色 · 导入于 <date>` /
//     `克隆模型 · 上传音频即可克隆音色 · 导入于 <date>`, a threads chip (合成设置), `生成引擎` / `克隆音色`, delete
//   footer: `本地引擎仅 VIP 可用` (bold) and `删除模型会保留由它生成的全部朗读引擎。`
// The original has no member check in this sheet: non-members can import and create engines; the gate is in synthesis (a bdtts
// engine speaks `您好，本地引擎仅支持会员使用。` for them, util/audio/tts_controller.dart).
// Replica: the picker accepts any file (zip, release tar.bz2, vocos .onnx; iOS cannot filter on `tar.bz2`), and a down.json entry
// that names such a file is downloaded here with progress, then imported; other entries open in the browser as in the original.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/widgets.dart';
import '../../../util/audio/local/local_tts_downloads.dart';
import '../../../util/audio/local/local_tts_manager.dart';
import '../../../util/toast.dart';
import 'local_engines.dart';

abstract class LocalEngineSheet {
  static const String title = '本地引擎 · 模型管理';
  static const String empty = '尚未导入模型包\n\n点右上角「导入模型包」选择 zip 模型文件';
  static const String vipNotice = '本地引擎仅 VIP 可用';
  static const String keepNotice = '删除模型会保留由它生成的全部朗读引擎。';
  static const String iosThreads =
      'iOS：线程数越高生成越快，但 CPU 占用和功耗随之增加，设备可能发热。锁屏/后台听书时 iOS 会监控 CPU，过高可能导致应用被系统终止（后台 60 秒窗口平均超 0.8 核杀进程）, 如果需要使用更多性能请在前台听书。';
  static const String desktopThreads = '桌面端：线程数越高生成越快，但会占用更多 CPU 资源，影响其他程序运行。';

  /// Opens the model manager.
  static Future<void> show(BuildContext context) async {
    await _sheet<void>(context, (ctx, controller) => LocalModelManager(controller: controller));
    await LocalEngines.stopPreview();
  }

  static Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext, ScrollController) builder) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: builder,
        ),
      );
}

Widget _handle(BuildContext context) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
      ),
    );

/// A modal "working" dialog around [job].
Future<T> _busy<T>(BuildContext context, String text, Future<T> Function() job) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ]),
      ),
    ),
  );
  try {
    return await job();
  } finally {
    nav.pop();
  }
}

class LocalModelManager extends StatefulWidget {
  final ScrollController? controller;
  const LocalModelManager({super.key, this.controller});

  @override
  State<LocalModelManager> createState() => _LocalModelManagerState();
}

class _LocalModelManagerState extends State<LocalModelManager> {
  List<LocalTtsModel> _models = LocalTtsManager.models;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      _models = await LocalTtsManager.load();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- import / download

  Future<void> _import() async {
    File? f;
    try {
      f = await DeviceIo.pickFile();
    } catch (e) {
      Toast.show('选择文件失败:$e', iserror: true);
      return;
    }
    if (f == null || !mounted) return;
    final path = f.path;
    await _busy(context, '正在导入模型包...', () => LocalEngines.importFile(path));
    await reload();
  }

  Future<void> _download() async {
    Map<String, String>? list;
    try {
      list = await _busy(context, '加载中...', LocalTtsDownloads.fetchList);
    } catch (e) {
      Toast.show('获取下载地址失败：$e', iserror: true);
      return;
    }
    if (list == null) return Toast.show('获取下载地址失败', iserror: true);
    if (list.isEmpty) return Toast.show('暂无可用下载地址', iserror: true);
    if (!mounted) return;
    final entries = list;
    final url = entries.length == 1
        ? entries.values.first
        : await LocalEngineSheet._sheet<String>(
            context,
            (ctx, controller) => SafeArea(
              child: Column(children: [
                _handle(ctx),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('下载模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: ListView(controller: controller, children: [
                    for (final e in entries.entries)
                      ListTile(
                        key: Key('local_down_${e.key}'),
                        title: Text(e.key),
                        subtitle: Text(LocalTtsDownloads.fileName(e.value), style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Icon(LocalTtsDownloads.isDirect(e.value) ? Icons.download_outlined : Icons.open_in_new, size: 18),
                        onTap: () => Navigator.of(ctx).pop(e.value),
                      ),
                  ]),
                ),
              ]),
            ),
          );
    if (url == null || !mounted) return;
    if (!LocalTtsDownloads.isDirect(url)) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final file = await _fetch(url);
    if (file == null || !mounted) return;
    await _busy(context, '正在导入模型包...', () => LocalEngines.importFile(file.path));
    LocalTtsDownloads.clean(file);
    await reload();
  }

  /// Downloads with a progress dialog; null when cancelled or failed.
  Future<File?> _fetch(String url) async {
    final progress = ValueNotifier<double?>(null);
    final cancel = CancelToken();
    final name = LocalTtsDownloads.fileName(url);
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('正在下载: $name', style: const TextStyle(fontSize: 15)),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: v),
              const SizedBox(height: 8),
              Text(v == null ? '下载中...' : '${(v * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [TextButton(key: const Key('local_down_cancel'), onPressed: () => cancel.cancel(), child: const Text('取消'))],
        ),
      ),
    );
    try {
      return await LocalTtsDownloads.download(url, cancel: cancel, onProgress: (got, total) {
        if (total > 0) progress.value = got / total;
      });
    } on DioException catch (e) {
      Toast.show(CancelToken.isCancel(e) ? '下载已取消' : '下载失败: ${e.message ?? e}', iserror: !CancelToken.isCancel(e));
      return null;
    } catch (e) {
      Toast.show('下载失败: $e', iserror: true);
      return null;
    } finally {
      nav.pop();
    }
  }

  // ---------------------------------------------------------------- per model

  Future<void> _delete(LocalTtsModel m) async {
    if (!await Dialogs.confirm(context, '删除模型', '确定删除模型「${m.name}」吗？\n由它生成的全部朗读引擎会被保留。', danger: true)) return;
    if (!mounted) return;
    await _busy(context, '正在删除模型...', () => LocalEngines.deleteModel(m.name));
    await reload();
  }

  Future<void> _settings(LocalTtsModel m) async {
    int? threads = m.numThreads;
    int? steps = m.numSteps;
    final max = LocalTtsManager.maxThreads.clamp(1, 16);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final cs = Theme.of(ctx).colorScheme;
        Widget chip(String label, bool on, VoidCallback tap, {Key? key}) =>
            ChoiceChip(key: key, label: Text(label), selected: on, onSelected: (_) => set(tap), visualDensity: VisualDensity.compact);
        return AlertDialog(
          title: Text('${m.name}\n合成设置', style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('线程数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('当前：${threads == null ? '默认（按平台自动分配）' : '$threads 线程'}', style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip('默认', threads == null, () => threads = null, key: const Key('local_threads_default')),
                for (var i = 1; i <= max; i++) chip('$i', threads == i, () => threads = i, key: Key('local_threads_$i')),
              ]),
              if (m.isClone) ...[
                const SizedBox(height: 14),
                const Text('流匹配步数（仅克隆模型）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('当前：${steps == null ? '默认（4 步）' : '$steps 步'}', style: TextStyle(fontSize: 12, color: cs.outline)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  chip('默认', steps == null, () => steps = null),
                  for (final s in const [4, 8, 12, 16, 20, 24, 32]) chip('$s', steps == s, () => steps = s, key: Key('local_steps_$s')),
                ]),
                const SizedBox(height: 4),
                Text('步数越多音质越好（电音越少），但合成越慢。建议 8~16 步。', style: TextStyle(fontSize: 12, color: cs.outline)),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(Platform.isIOS ? LocalEngineSheet.iosThreads : LocalEngineSheet.desktopThreads, style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            ElevatedButton(key: const Key('local_settings_save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
          ],
        );
      }),
    );
    if (saved != true) return;
    await LocalEngines.saveSettings(m, threads: threads, steps: steps);
    await reload();
  }

  Future<void> _engines(LocalTtsModel m) async {
    if (m.isClone) {
      await LocalVoicePages.clone(context, m);
    } else {
      await LocalVoicePages.voices(context, m);
    }
    await reload();
  }

  Widget _tile(BuildContext context, int i) {
    final m = _models[i];
    final cs = Theme.of(context).colorScheme;
    final when = LocalEngines.date(m.importTime);
    return Container(
      key: Key('local_model_${m.name}'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(border: Border.all(color: cs.outline.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(m.isClone ? Icons.record_voice_over_outlined : Icons.memory_outlined, size: 22, color: cs.primary),
        ),
        title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.isClone ? '克隆模型 · 上传音频即可克隆音色 · 导入于 $when' : '${m.voices.length} 款音色 · 导入于 $when',
              style: const TextStyle(fontSize: 12, height: 1.35)),
          const SizedBox(height: 4),
          GestureDetector(
            key: Key('local_settings_${m.name}'),
            onTap: () => _settings(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.tune, size: 12, color: cs.primary),
                const SizedBox(width: 3),
                Text('${m.numThreads?.toString() ?? '默认'} 线程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
              ]),
            ),
          ),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(
            key: Key('local_engines_${m.name}'),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _engines(m),
            child: Text(m.isClone ? '克隆音色' : '生成引擎', style: const TextStyle(fontSize: 12)),
          ),
          IconButton(key: Key('local_delete_${m.name}'), tooltip: '删除模型', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _delete(m)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buttons = [
      OutlinedButton.icon(
        key: const Key('local_download'),
        icon: const Icon(Icons.cloud_download_outlined, size: 16),
        label: const Text('下载模型', style: TextStyle(fontSize: 13)),
        onPressed: _download,
      ),
      const SizedBox(width: 8),
      ElevatedButton.icon(
        key: const Key('local_import'),
        icon: const Icon(Icons.file_open_outlined, size: 16),
        label: const Text('导入模型包', style: TextStyle(fontSize: 13)),
        onPressed: _import,
      ),
    ];
    final close = IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).maybePop());
    const title = Text(LocalEngineSheet.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
    return Column(children: [
      _handle(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
        child: LayoutBuilder(
          builder: (ctx, c) => c.maxWidth < 500
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [close, title]),
                  Padding(padding: const EdgeInsets.only(left: 12), child: Row(children: buttons)),
                ])
              : Row(children: [close, title, const Spacer(), ...buttons]),
        ),
      ),
      Expanded(
        child: _models.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(LocalEngineSheet.empty, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6)),
                ),
              )
            : Scrollbar(
                controller: widget.controller,
                child: ListView.builder(
                  controller: widget.controller,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _models.length,
                  itemBuilder: _tile,
                ),
              ),
      ),
      const Divider(height: 16),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text(LocalEngineSheet.vipNotice, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(LocalEngineSheet.keepNotice, style: TextStyle(fontSize: 12, color: cs.outline)),
          ]),
        ),
      ),
    ]);
  }
}

/// The voice list and the clone sheet of one model.
abstract class LocalVoicePages {
  /// `<model> · <n> 款音色`: filter by language / gender, preview, tap to name and add an engine.
  static Future<void> voices(BuildContext context, LocalTtsModel m) async {
    var lang = 'all', gender = 'all';
    var playing = -1;
    await LocalEngineSheet._sheet<void>(
      context,
      (ctx, controller) => StatefulBuilder(builder: (ctx, set) {
        final cs = Theme.of(ctx).colorScheme;
        final list = [
          for (final v in m.voices)
            if ((lang == 'all' || v.lang.toLowerCase().startsWith(lang)) && (gender == 'all' || v.gender == gender)) v,
        ];
        Widget filterChip(String label, String group, String value) {
          final on = (group == 'lang' ? lang : gender) == value;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: Key('local_filter_${group}_$value'),
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: on,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => set(() => group == 'lang' ? lang = value : gender = value),
            ),
          );
        }

        Future<void> add(LocalTtsVoice v) async {
          final name = await nameDialog(ctx, LocalEngines.defaultName(m, v));
          if (name == null) return;
          await LocalEngines.addVoice(m, v, name);
          set(() {});
        }

        Future<void> play(LocalTtsVoice v) async {
          set(() => playing = v.id);
          await LocalEngines.preview(m, voice: v);
          if (ctx.mounted) set(() => playing = -1);
        }

        return Column(children: [
          _handle(ctx),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text('${m.name} · ${m.voices.length} 款音色',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              filterChip('全部', 'lang', 'all'),
              filterChip('中文', 'lang', 'zh'),
              filterChip('英文', 'lang', 'en'),
              const SizedBox(width: 12),
              filterChip('不限', 'gender', 'all'),
              filterChip('女声', 'gender', 'female'),
              filterChip('男声', 'gender', 'male'),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('点播放键试听音色；点击音色命名后生成朗读引擎。', style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: controller,
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final v = list[i];
                  final added = LocalEngines.exists(m.name, v.id);
                  final female = v.gender == 'female';
                  final tint = female ? Colors.pink : (v.gender == 'male' ? Colors.blue : cs.primary);
                  return ListTile(
                    key: Key('local_voice_${v.id}'),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(female ? Icons.face_3_outlined : Icons.face_outlined, size: 22, color: tint),
                    ),
                    title: Row(children: [
                      Flexible(child: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (added)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text('已添加', style: TextStyle(fontSize: 11, color: cs.primary)),
                        ),
                    ]),
                    subtitle: Text('语言 ${v.lang} · id ${v.id}', style: const TextStyle(fontSize: 12, height: 1.35)),
                    trailing: playing == v.id
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            key: Key('local_play_${v.id}'),
                            tooltip: '试听',
                            icon: Icon(Icons.play_circle_outline, color: cs.primary),
                            onPressed: playing >= 0 ? null : () => play(v),
                          ),
                    onTap: () => add(v),
                  );
                },
              ),
            ),
          ),
        ]);
      }),
    );
    await LocalEngines.stopPreview();
  }

  /// 命名朗读引擎; null when cancelled.
  static Future<String?> nameDialog(BuildContext context, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.7 < 280 ? 320 : MediaQuery.of(ctx).size.width * 0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('命名朗读引擎', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(key: const Key('local_engine_name'), controller: c, autofocus: true),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(key: const Key('local_engine_name_ok'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('确定')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// 克隆音色: reference WAV (3-10 s), its words, a name; 试听 / 创建.
  static Future<void> clone(BuildContext context, LocalTtsModel m) async {
    CloneReference? ref;
    final refText = TextEditingController();
    final name = TextEditingController(text: '克隆音色');
    var previewing = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, set) {
          final cs = Theme.of(ctx).colorScheme;
          Future<void> pick() async {
            try {
              final f = await DeviceIo.pickFile(extensions: const ['wav']);
              if (f == null) return;
              final r = LocalEngines.readReference(f);
              if (r != null) set(() => ref = r);
            } catch (e) {
              Toast.show('读取音频失败：$e', iserror: true);
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _handle(ctx),
              const Text('克隆音色', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text(m.name, style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text(
                    '参考音频：${ref == null ? '未选择' : '${ref!.fileName}（${ref!.seconds.toStringAsFixed(1)} 秒）'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(key: const Key('local_clone_pick'), onPressed: pick, child: const Text('选择')),
              ]),
              Text('建议 3-10 秒清晰人声；克隆模型的情感和语气由参考音频决定。同一模型可创建无数个引擎。', style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('local_clone_text'),
                controller: refText,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '参考音频中说的文字'),
              ),
              TextField(key: const Key('local_clone_name'), controller: name, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('local_clone_preview'),
                    onPressed: previewing
                        ? null
                        : () async {
                            set(() => previewing = true);
                            await LocalEngines.preview(m, reference: ref, refText: refText.text);
                            if (ctx.mounted) set(() => previewing = false);
                          },
                    child: previewing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('试听'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('local_clone_create'),
                    onPressed: () async {
                      final e = await LocalEngines.addClone(m, name: name.text, reference: ref, refText: refText.text);
                      if (e != null && ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('创建'),
                  ),
                ),
              ]),
            ]),
          );
        }),
      ),
    );
    await LocalEngines.stopPreview();
  }
}
