// pages/tts/multi_role_edit.dart — 新建多角色规则 / 编辑多角色规则 (`MultiRoleEdit`, 107 functions with the role dialog and the library
// import): 规则名称 (`请输入规则名称`, `名称已存在`), 引擎设置 (旁白引擎 / 默认男性对话引擎 / 默认女性对话引擎, each an engine + voice),
// 角色列表 (n) with 添加 (`暂无角色` / `点击上方"添加"按钮创建角色`; role dialog: name, 性别 男/女/未知, engine `引擎: …`), delete
// (`确定要删除该角色吗？`) and 从角色库导入 (the AI character library of a book, `所选角色均已存在`, `已导入 n 个角色`).
// Save checks `请选择旁白朗读引擎` / `请选择男性朗读引擎` / `请选择女性朗读引擎` / `角色 x 为选择朗读引擎` and stores an `HttpTts` with
// tp = 多角色 (global) or the per-book setup when [bookUrl] is given (`Tts.saveForBook`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/tts.dart';
import '../../models/httptts.dart';
import '../../storage/setting.dart';
import '../../theme/widgets.dart';
import '../../util/audio/tts_controller.dart';
import '../../util/toast.dart';

class MultiRoleEdit extends StatefulWidget {
  final HttpTts? engine;

  /// Non-empty: edit the multi-role setup of this book.
  final String bookUrl;

  /// Key of the AI character library (`Setting.getAiCharacters`), usually the book url.
  final String bookKey;
  const MultiRoleEdit({super.key, this.engine, this.bookUrl = '', this.bookKey = ''});

  @override
  State<MultiRoleEdit> createState() => _MultiRoleEditState();
}

class _MultiRoleEditState extends State<MultiRoleEdit> {
  late final HttpTts e = widget.engine != null
      ? HttpTts.fromJson(widget.engine!.toJson())
      : (TTSData.forBook(widget.bookUrl) != null ? HttpTts.fromJson(TTSData.forBook(widget.bookUrl)!.toJson()) : HttpTts(tp: TtsKind.multiRole.tp));
  late final TextEditingController _name = TextEditingController(text: e.name);
  late List<TtsRole> _roles = [for (final r in e.roles) if (r is Map) TtsRole.fromJson(Map<String, dynamic>.from(r))];

  static const List<String> genders = ['男', '女', '未知'];

  /// Engines a role can use: the system voice and every non multi-role engine.
  List<HttpTts> get _choices => [TTSData.defaultEngine, ...TTSData.engines.where((x) => TtsKind.of(x) != TtsKind.multiRole)];

  String _engineName(String id) => id.isEmpty ? '未选择' : (TTSData.byId(id)?.name ?? '未知');

  Future<(String, String)?> _pickEngine(String title, String engineId, String voiceId) async {
    final list = _choices;
    final i = await Dialogs.choose(context, title, [for (final x in list) x.name], selected: list.indexWhere((x) => x.id == engineId));
    if (i == null || !mounted) return null;
    final voice = await Dialogs.input(context, '发音人', hint: '音色 id（可留空）', initial: list[i].id == engineId ? voiceId : '');
    return (list[i].id, voice ?? '');
  }

  Future<void> _role([int? index]) async {
    final r = index == null ? TtsRole(gender: 2) : TtsRole.fromJson(_roles[index].toJson());
    final name = TextEditingController(text: r.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(index == null ? '添加' : '编辑角色'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '角色')),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [for (var g = 0; g < 3; g++) ButtonSegment(value: g, label: Text(genders[g]))],
              selected: {r.gender.clamp(0, 2)},
              onSelectionChanged: (v) => setS(() => r.gender = v.first),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('引擎: ${_engineName(r.engineId)}'),
              subtitle: r.voiceId.isEmpty ? null : Text(r.voiceId),
              onTap: () async {
                final x = await _pickEngine('当前选择', r.engineId, r.voiceId);
                if (x != null) {
                  setS(() => r
                    ..engineId = x.$1
                    ..voiceId = x.$2);
                }
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    r.name = name.text.trim();
    if (r.name.isEmpty) return;
    if (_roles.asMap().entries.any((x) => x.key != index && x.value.name == r.name)) return Toast.show('名称已存在', iserror: true);
    setState(() {
      if (index == null) {
        _roles.add(r);
      } else {
        _roles[index] = r;
      }
    });
  }

  Future<void> _importLibrary() async {
    final lib = Setting.getAiCharacters(widget.bookKey.isEmpty ? widget.bookUrl : widget.bookKey);
    if (lib.isEmpty) return Toast.show('角色库还是空的');
    final have = _roles.map((r) => r.name).toSet();
    final fresh = lib.where((c) => !have.contains(c.name)).toList();
    if (fresh.isEmpty) return Toast.show('所选角色均已存在');
    setState(() => _roles = [..._roles, for (final c in fresh) TtsRole(name: c.name, gender: c.gender)]);
    Toast.show('已导入 ${fresh.length} 个角色');
  }

  Future<void> _save() async {
    e.name = _name.text.trim();
    if (e.name.isEmpty) return Toast.show('请输入规则名称', iserror: true);
    if (e.narrationEngineId.isEmpty) return Toast.show('请选择旁白朗读引擎', iserror: true);
    if (e.defaultMaleDialogueEngineId.isEmpty) return Toast.show('请选择男性朗读引擎', iserror: true);
    if (e.defaultFemaleDialogueEngineId.isEmpty) return Toast.show('请选择女性朗读引擎', iserror: true);
    for (final r in _roles) {
      if (r.engineId.isEmpty) return Toast.show('角色 ${r.name} 为选择朗读引擎', iserror: true);
    }
    await TTSData.load();
    if (widget.bookUrl.isEmpty && TTSData.engines.any((x) => x.name == e.name && x.id != e.id)) return Toast.show('名称已存在', iserror: true);
    e
      ..tp = TtsKind.multiRole.tp
      ..roles = [for (final r in _roles) r.toJson()];
    try {
      if (widget.bookUrl.isNotEmpty) {
        await Tts.saveForBook(widget.bookUrl, e);
      } else if (e.id.isEmpty) {
        await Tts.add(e);
      } else {
        await Tts.update(e);
      }
      Toast.show('保存成功');
      Get.back();
    } catch (err) {
      Toast.show('保存失败：$err', iserror: true);
    }
  }

  Widget _engineRow(String title, String id, String voice, void Function(String, String) set) => ListTile(
        title: Text(title),
        subtitle: Text(voice.isEmpty ? _engineName(id) : '${_engineName(id)} · $voice'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final x = await _pickEngine(title, id, voice);
          if (x != null) setState(() => set(x.$1, x.$2));
        },
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.engine == null && TTSData.forBook(widget.bookUrl) == null ? '新建多角色规则' : '编辑多角色规则'),
        actions: [TextButton(key: const Key('mr_save'), onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('mr_name'),
            controller: _name,
            decoration: const InputDecoration(labelText: '规则名称', hintText: '请输入规则名称', border: OutlineInputBorder()),
          ),
        ),
        SectionCard(title: '引擎设置', children: [
          _engineRow('旁白引擎', e.narrationEngineId, e.narrationVoiceId, (a, b) => e
            ..narrationEngineId = a
            ..narrationVoiceId = b),
          _engineRow('默认男性对话引擎', e.defaultMaleDialogueEngineId, e.defaultMaleDialogueVoiceId, (a, b) => e
            ..defaultMaleDialogueEngineId = a
            ..defaultMaleDialogueVoiceId = b),
          _engineRow('默认女性对话引擎', e.defaultFemaleDialogueEngineId, e.defaultFemaleDialogueVoiceId, (a, b) => e
            ..defaultFemaleDialogueEngineId = a
            ..defaultFemaleDialogueVoiceId = b),
        ]),
        SectionCard(title: '角色列表 (${_roles.length})', children: [
          Row(children: [
            TextButton.icon(onPressed: () => _role(), icon: const Icon(Icons.add), label: const Text('添加')),
            TextButton.icon(onPressed: _importLibrary, icon: const Icon(Icons.people_outline), label: const Text('从角色库导入')),
          ]),
          if (_roles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('暂无角色'),
                Text('点击上方"添加"按钮创建角色', style: TextStyle(fontSize: 12, color: cs.outline)),
              ]),
            ),
          for (var i = 0; i < _roles.length; i++)
            ListTile(
              title: Text('${_roles[i].name}（${genders[_roles[i].gender.clamp(0, 2)]}）'),
              subtitle: Text('引擎: ${_engineName(_roles[i].engineId)}${_roles[i].voiceId.isEmpty ? '' : ' · ${_roles[i].voiceId}'}'),
              onTap: () => _role(i),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await Dialogs.confirm(context, '删除确认', '确定要删除该角色吗？', danger: true)) return;
                  setState(() => _roles = [..._roles]..removeAt(i));
                },
              ),
            ),
        ]),
      ]),
    );
  }
}
