// pages/tts/tts_edit.dart — 朗读引擎编辑 (`EditTts`, 13 functions) for HTTP engines: 名称 (`请输入名称`, `名称重复`), the engine
// definition (`html(html 代码或者网址)`: the Legado HttpTTS url template, header, contentType), 需要登录, and the 更多 menu
// 复制 (`引擎已复制`) / 粘贴 (`剪贴板为空!` / `粘贴失败:`) / 编辑代码 (code.dart) / 试听. Save → `保存成功` / `保存失败：…`.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/tts.dart';
import '../../models/httptts.dart';
import '../../util/audio/tts_controller.dart';
import '../../util/toast.dart';
import 'code.dart';
import 'tts_setting.dart';

class EditTts extends StatefulWidget {
  final HttpTts? engine;
  const EditTts({super.key, this.engine});

  @override
  State<EditTts> createState() => _EditTtsState();
}

class _EditTtsState extends State<EditTts> {
  late HttpTts e = widget.engine == null ? HttpTts(tp: TtsKind.http.tp) : HttpTts.fromJson(widget.engine!.toJson());
  late final TextEditingController _name = TextEditingController(text: e.name);
  late final TextEditingController _url = TextEditingController(text: '${e.html['url'] ?? ''}');
  late final TextEditingController _header = TextEditingController(text: _headerText(e.html['header']));
  late final TextEditingController _type = TextEditingController(text: '${e.html['contentType'] ?? ''}');

  static String _headerText(Object? h) => h == null ? '' : (h is String ? h : jsonEncode(h));

  void _collect() {
    e.name = _name.text.trim();
    e.html = {
      ...e.html,
      'name': e.name,
      'url': _url.text.trim(),
      if (_header.text.trim().isNotEmpty) 'header': _header.text.trim() else 'header': null,
      if (_type.text.trim().isNotEmpty) 'contentType': _type.text.trim() else 'contentType': null,
    }..removeWhere((_, v) => v == null);
  }

  void _load(HttpTts x) {
    setState(() {
      e = x;
      _name.text = x.name;
      _url.text = '${x.html['url'] ?? ''}';
      _header.text = _headerText(x.html['header']);
      _type.text = '${x.html['contentType'] ?? ''}';
    });
  }

  Future<void> _save() async {
    _collect();
    if (e.name.isEmpty) return Toast.show('请输入名称', iserror: true);
    if ('${e.html['url'] ?? ''}'.isEmpty) return Toast.show('请输入html', iserror: true);
    await TTSData.load();
    if (TTSData.engines.any((x) => x.name == e.name && x.id != e.id)) return Toast.show('名称重复', iserror: true);
    try {
      if (e.id.isEmpty) {
        e = await Tts.add(e);
      } else {
        await Tts.update(e);
      }
      Toast.show('保存成功');
      Get.back();
    } catch (err) {
      Toast.show('保存失败：$err', iserror: true);
    }
  }

  Future<void> _menu(String v) async {
    _collect();
    switch (v) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: jsonEncode(e.html)));
        Toast.show('引擎已复制');
      case 'paste':
        try {
          final d = await Clipboard.getData(Clipboard.kTextPlain);
          final t = d?.text ?? '';
          if (t.trim().isEmpty) return Toast.show('剪贴板为空!', iserror: true);
          final m = Map<String, dynamic>.from(jsonDecode(t) as Map);
          _load(HttpTts(id: e.id, name: '${m['name'] ?? e.name}', tp: TtsKind.http.tp, candel: true, html: m));
        } catch (err) {
          Toast.show('粘贴失败:$err', iserror: true);
        }
      case 'code':
        final r = await Get.to<String>(() => CodePage(code: const JsonEncoder.withIndent('  ').convert(e.html)));
        if (r == null) return;
        try {
          _load(HttpTts.fromJson(e.toJson())..html = Map<String, dynamic>.from(jsonDecode(r) as Map));
        } catch (err) {
          Toast.show('保存失败：$err', iserror: true);
        }
      case 'test':
        try {
          await TtsController.speak(e, TTsSetting.sample);
        } catch (err) {
          Toast.show('$err', iserror: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, [String? hint]) => InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);
    return Scaffold(
      appBar: AppBar(title: const Text('朗读引擎编辑'), actions: [
        IconButton(key: const Key('tts_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: _menu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'test', child: Text('试听')),
            PopupMenuItem(value: 'code', child: Text('编辑代码')),
            PopupMenuItem(value: 'copy', child: Text('复制')),
            PopupMenuItem(value: 'paste', child: Text('粘贴')),
          ],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(key: const Key('tts_name'), controller: _name, decoration: deco('名称', '请输入名称')),
        const SizedBox(height: 12),
        TextField(
          key: const Key('tts_url'),
          controller: _url,
          minLines: 3,
          maxLines: 8,
          decoration: deco('html(html 代码或者网址)', 'https://host/tts?text={{java.encodeURI(speakText)}}&rate={{speakSpeed}}'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _header, minLines: 1, maxLines: 4, decoration: deco('header', '{"User-Agent":"..."}')),
        const SizedBox(height: 12),
        TextField(controller: _type, decoration: deco('contentType', 'audio/.*')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('需要登录'),
          value: e.login,
          onChanged: (v) => setState(() => e.login = v),
        ),
      ]),
    );
  }
}
