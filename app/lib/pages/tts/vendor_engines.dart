// pages/tts/vendor_engines.dart — the 火山引擎 and MiMo引擎 entries of 朗读引擎 (part of the original tts_setting.dart, kept in its own
// file here). Both create normal page engines (`tp` 0, util/audio/tts_page.dart templates) with the user's own credentials:
//   火山引擎 (0xfeafd8): 21 voices by scene, credentials dialog 火山引擎凭证 (App ID / Access Token → `volcano_tts_app_id` /
//     `volcano_tts_access_token`, 火山引擎凭证已保存), tap = add `火山-<name>(<女|男>声)` (该音色引擎已存在 / 已添加：…), batch import
//     (可一键批量导入，剩余未添加：n 个 / 全部角色已添加完毕).
//   MiMo引擎 (0xfe8ae8): one API key for all three (`mi_ai_api_key`, 设置 MiMo API Key, Key 已保存 / 已清除 Key) and
//     预置音色 (MiMo V2.5 · 中文 4 款音色, 可重复添加, 添加「x」引擎 with 自定义名称 + optional instruction),
//     音色克隆 (MiMo 音色克隆: mp3/wav ≤ 300 KB reference audio → data URI) and 音色设计 (MiMo 音色设计（文本描述定制）: description
//     ≤ 500 characters).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/mimo_tts.dart';
import '../../ai/volcano_tts.dart';
import '../../data/tts.dart';
import '../../models/httptts.dart';
import '../../theme/widgets.dart';
import '../../util/audio/tts_page.dart';
import '../../util/toast.dart';

abstract class VendorEngines {
  static const String volcanoMissing =
      '未配置火山引擎凭证（App ID / Access Token），添加的引擎将无法朗读。请点右上角「凭证」按钮填写。\n获取地址：${VolcanoTTS.consoleUrl}';
  static const String mimoFree = '目前 MiMo V2.5 TTS 为限时免费，不代表您使用时依旧免费，具体请以官方说明为准。';

  static String volcanoName(VolcanoVoice v) => '火山-${v.name}(${v.gender}声)';

  static bool _exists(String name) => TTSData.engines.any((e) => e.name == name);

  static Future<HttpTts> _add(String name, String page) => Tts.add(HttpTts(name: name, tp: 0, candel: true, html: {'page': page}));

  /// Adds the engine of one Volcano voice; false when it already exists.
  static Future<bool> addVolcano(VolcanoVoice v) async {
    final name = volcanoName(v);
    if (_exists(name)) {
      Toast.show('该音色引擎已存在');
      return false;
    }
    await _add(name, TtsPages.volcanoPage(v.id));
    Toast.show('已添加：$name');
    return true;
  }

  static Future<HttpTts> addMimo(MimoVoice v, {String name = '', String instruction = ''}) async {
    final n = name.trim().isEmpty ? 'MiMo-${v.name}(${v.female ? '女' : '男'}声)' : name.trim();
    final e = await _add(n, TtsPages.mimoPage(v.id, instruction: instruction.trim()));
    Toast.show('已添加：$n（音色=${v.id}${instruction.trim().isEmpty ? '' : '，有自然语言指令 ${instruction.trim()}'}）');
    return e;
  }

  static Future<HttpTts?> addMimoClone({required String name, required String referenceAudio, String instruction = ''}) async {
    if (name.trim().isEmpty) {
      Toast.show('引擎名称不能为空', iserror: true);
      return null;
    }
    if (referenceAudio.isEmpty) {
      Toast.show('音频读取为空，请重新选择', iserror: true);
      return null;
    }
    final e = await _add(name.trim(), TtsPages.mimoClonePage(referenceAudio, instruction: instruction.trim()));
    Toast.show('已添加克隆引擎：${name.trim()}');
    return e;
  }

  static Future<HttpTts?> addMimoDesign({required String name, required String description, String instruction = ''}) async {
    final d = description.trim();
    if (name.trim().isEmpty) {
      Toast.show('引擎名称不能为空', iserror: true);
      return null;
    }
    if (d.isEmpty) {
      Toast.show('音色文本描述不能为空', iserror: true);
      return null;
    }
    if (d.length > MimoTTS.maxDesign) {
      Toast.show('音色文本描述过长（≤500字）', iserror: true);
      return null;
    }
    final e = await _add(name.trim(), TtsPages.mimoDesignPage(d, instruction: instruction.trim()));
    Toast.show('已添加音色设计引擎：${name.trim()}（描述 ${d.length} 字${instruction.trim().isEmpty ? '' : '，含自然语言指令 ${instruction.trim()}'}）');
    return e;
  }

  // ---------------------------------------------------------------- dialogs

  static Future<void> volcanoCredentials(BuildContext context) async {
    final id = TextEditingController(text: VolcanoTTS.appId);
    final tk = TextEditingController(text: VolcanoTTS.accessToken);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('火山引擎凭证'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const Key('volc_appid'), controller: id, decoration: const InputDecoration(labelText: 'App ID', hintText: '在此粘贴你的 App ID')),
            TextField(key: const Key('volc_token'), controller: tk, decoration: const InputDecoration(labelText: 'Access Token', hintText: '在此粘贴你的 Access Token')),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => launchUrl(Uri.parse(VolcanoTTS.consoleUrl), mode: LaunchMode.externalApplication),
              child: Text('去火山控制台获取 →  ${VolcanoTTS.consoleUrl}', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.primary)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(key: const Key('volc_save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await VolcanoTTS.saveCredentials(id.text, tk.text);
    Toast.show('火山引擎凭证已保存');
  }

  static Future<void> mimoKey(BuildContext context) async {
    final key = TextEditingController(text: MimoTTS.apiKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置 MiMo API Key'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(key: const Key('mimo_key'), controller: key, decoration: const InputDecoration(labelText: 'MiMo API Key', hintText: '请粘贴你的 MiMo API Key')),
          const SizedBox(height: 8),
          Text('Key 保存在本地，仅用于当前设备。', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('https://mimo.mi.com/'), mode: LaunchMode.externalApplication),
            child: const Text('官方网站 / 获取 Key'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(key: const Key('mimo_key_save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存（清空）')),
        ],
      ),
    );
    if (ok != true) return;
    await MimoTTS.saveKey(key.text);
    Toast.show(key.text.trim().isEmpty ? '已清除 Key' : 'Key 已保存');
  }

  /// 火山引擎 sheet.
  static Future<void> volcano(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
          final cs = Theme.of(ctx).colorScheme;
          final configured = VolcanoTTS.appId.isNotEmpty && VolcanoTTS.accessToken.isNotEmpty;
          final left = VolcanoTTS.voices.where((v) => !_exists(volcanoName(v))).toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                title: const Text('火山引擎', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('字节跳动 · 21 款音色'),
                trailing: TextButton.icon(
                  key: const Key('volc_creds'),
                  onPressed: () async {
                    await volcanoCredentials(ctx);
                    setS(() {});
                  },
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: Text(configured ? '凭证已配置，点击修改' : '未配置凭证，点击填写'),
                ),
              ),
              if (!configured)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(volcanoMissing, style: TextStyle(fontSize: 12, color: cs.error))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(children: [
                  Expanded(child: Text(left.isEmpty ? '全部角色已添加完毕' : '可一键批量导入，剩余未添加：${left.length} 个', style: TextStyle(fontSize: 12, color: cs.outline))),
                  if (left.isNotEmpty)
                    TextButton(
                      key: const Key('volc_all'),
                      onPressed: () async {
                        try {
                          for (final v in left) {
                            await _add(volcanoName(v), TtsPages.volcanoPage(v.id));
                          }
                          Toast.show('已添加：${left.length} 个');
                        } catch (e) {
                          Toast.show('批量导入失败:$e', iserror: true);
                        }
                        setS(() {});
                      },
                      child: const Text('批量导入'),
                    ),
                ]),
              ),
              Expanded(
                child: ListView(children: [
                  for (final scene in const ['通用场景', '有声阅读', '智能助手']) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 2), child: Text(scene, style: TextStyle(color: cs.primary))),
                    for (final v in VolcanoTTS.voices.where((v) => v.scene == scene))
                      ListTile(
                        key: Key('volc_${v.id}'),
                        dense: true,
                        leading: Icon(v.female ? Icons.face_3_outlined : Icons.face_outlined),
                        title: Text('${v.name} · ${v.gender}'),
                        subtitle: Text(v.description),
                        trailing: _exists(volcanoName(v)) ? const Text('已添加') : const Icon(Icons.add),
                        onTap: () async {
                          await addVolcano(v);
                          setS(() {});
                        },
                      ),
                  ],
                ]),
              ),
            ]),
          );
        }),
      );

  /// MiMo引擎 sheet: key + the three modes.
  static Future<void> mimo(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
          final has = MimoTTS.apiKey.isNotEmpty;
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                title: const Text('MiMo引擎', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(has ? '已设置：***' : '未设置（无法合成）'),
                trailing: TextButton(
                  key: const Key('mimo_set_key'),
                  onPressed: () async {
                    await mimoKey(ctx);
                    setS(() {});
                  },
                  child: const Text('设置 Key'),
                ),
              ),
              ListTile(
                key: const Key('mimo_preset'),
                leading: const Icon(Icons.record_voice_over_outlined),
                title: const Text('预置音色'),
                subtitle: const Text('MiMo V2.5 · 中文 4 款音色'),
                onTap: () => _mimoPreset(ctx),
              ),
              ListTile(
                key: const Key('mimo_clone'),
                leading: const Icon(Icons.mic_none_outlined),
                title: const Text('音色克隆'),
                subtitle: const Text('上传一段参考音频（mp3/wav，≤300KB，建议 ≤15s），让 MiMo 复刻该音色生成新引擎'),
                onTap: () => _mimoClone(ctx),
              ),
              ListTile(
                key: const Key('mimo_design'),
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('音色设计'),
                subtitle: const Text('用自然语言描述你想要的音色（如「温柔御姐，语速慢」），让 MiMo 生成全新音色引擎'),
                onTap: () => _mimoDesign(ctx),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(mimoFree, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline))),
            ]),
          );
        }),
      );

  static Future<void> _mimoPreset(BuildContext context) async {
    final v = await showDialog<MimoVoice>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('MiMo V2.5 · 中文 4 款音色'), children: [
        for (final v in MimoTTS.voices)
          SimpleDialogOption(
            key: Key('mimo_voice_${v.id}'),
            onPressed: () => Navigator.of(ctx).pop(v),
            child: ListTile(title: Text('${v.name} · ${v.female ? '女' : '男'} · 可重复添加'), subtitle: Text(v.description)),
          ),
      ]),
    );
    if (v == null || !context.mounted) return;
    final name = TextEditingController();
    final ins = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加「${v.name}」引擎'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: '自定义名称')),
          TextField(controller: ins, decoration: const InputDecoration(labelText: '自然语言控制（可选）', hintText: '如：语速慢，温柔')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(key: const Key('mimo_add'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true) await addMimo(v, name: name.text, instruction: ins.text);
  }

  static Future<void> _mimoClone(BuildContext context) async {
    final name = TextEditingController();
    final ins = TextEditingController();
    var audio = '';
    var label = '点击选择 mp3/wav 音频文件';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('MiMo 音色克隆'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('1. 参考音频（仅支持 mp3 / wav，≤300KB，建议时长 ≤15s）'),
              TextButton.icon(
                icon: const Icon(Icons.audio_file_outlined),
                label: Text(label),
                onPressed: () async {
                  try {
                    final f = await DeviceIo.pickFile(extensions: const ['mp3', 'wav']);
                    if (f == null) return;
                    final bytes = await f.readAsBytes();
                    final kb = (bytes.length / 1024).ceil();
                    if (bytes.isEmpty) return Toast.show('音频读取为空，请重新选择', iserror: true);
                    if (kb > 300) return Toast.show('文件过大（${kb}KB），克隆参考音频请使用 ≤300KB（建议时长 ≤15s）', iserror: true);
                    audio = MimoTTS.dataUri(bytes, f.path);
                    setS(() => label = '${f.uri.pathSegments.last} · $kb KB');
                  } catch (e) {
                    Toast.show('选择音频失败:$e', iserror: true);
                  }
                },
              ),
              TextField(controller: name, decoration: const InputDecoration(labelText: '2. 引擎名称（必填，自定义）', hintText: '例如：我的声音 / 角色-阿明-讲故事')),
              TextField(controller: ins, maxLines: 3, decoration: const InputDecoration(labelText: '3. 自然语言控制（可选）')),
              const SizedBox(height: 8),
              Text(mimoFree, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('添加')),
          ],
        ),
      ),
    );
    if (ok == true) await addMimoClone(name: name.text, referenceAudio: audio, instruction: ins.text);
  }

  static Future<void> _mimoDesign(BuildContext context) async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final ins = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MiMo 音色设计（文本描述定制）'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('mimo_design_name'), controller: name, decoration: const InputDecoration(labelText: '1. 引擎名称（必填，自定义）', hintText: '例如：御姐-温柔 / 青年-新闻播报')),
            TextField(
              key: const Key('mimo_design_desc'),
              controller: desc,
              maxLines: 4,
              maxLength: MimoTTS.maxDesign,
              decoration: const InputDecoration(
                labelText: '2. 音色文本描述（必填，建议 ≤500字）',
                hintText: '用自然语言描述你想要的音色，例如：\n一位 28 岁的青年女性，声音清澈明亮，语气温柔坚定，\n像深夜电台主播在讲散文，语速偏慢。',
              ),
            ),
            TextField(
              controller: ins,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '3. 自然语言控制（可选）', hintText: '留空表示不加控制；例：\n朗读时带浅浅的呼吸感，句末轻轻回落，像在给朋友讲故事。'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(key: const Key('mimo_design_add'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true) await addMimoDesign(name: name.text, description: desc.text, instruction: ins.text);
  }
}
