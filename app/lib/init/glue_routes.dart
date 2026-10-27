// init/glue_routes.dart — named routes that sit between areas (lead-owned): pages of one area call them, the implementation lives
// in another area or needs pieces of several.
//   source_login / source_variable (argument: source url)  -> the sources area's login / variable dialogs
//   config_import ({type: file|url|qr})                    -> 添加配置: replace rules, TTS engines, TXT rules, highlight rules,
//                                                            book / RSS sources, exploration templates; detected by their fields
//   qread_import                                           -> bind the own reading backend first (its shelf API is not ported)
//   viewlog                                                -> the in-app message log
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/exploration.dart';
import '../data/highlight.dart';
import '../data/replace.dart';
import '../data/rss.dart';
import '../data/source.dart';
import '../data/tts.dart';
import '../data/txtrule.dart';
import '../common/nav.dart';
import '../pages/source/login_dialog.dart';
import '../pages/source/source_setting.dart';
import '../qread/qread.dart';
import '../util/toast.dart';
import '../util/webbook/model/book_source.dart';
import '../widget/base_page.dart';

abstract class GlueRoutes {
  static const names = {'source_login', 'source_variable', 'config_import', 'qread_import', 'viewlog'};

  static Future<bool> open(BuildContext context, String name, {Object? arguments}) async {
    switch (name) {
      case 'source_login':
      case 'source_variable':
        final raw = Sourcedata.byUrl('${arguments ?? ''}');
        if (raw == null) {
          Toast.show('书源不存在', iserror: true);
          return true;
        }
        final source = BookSource.fromJson(raw);
        if (!context.mounted) return true;
        if (name == 'source_login') {
          await showSourceLogin(context, source);
        } else {
          await showSourceVariableDialog(context, source);
        }
        return true;
      case 'config_import':
        final type = arguments is Map ? '${arguments['type']}' : '$arguments';
        await importConfig(context, type);
        return true;
      case 'qread_import':
        if (!Qread.isbind) {
          Toast.show('请先绑定轻阅读后端');
          if (context.mounted) await Nav.openNamed(context, 'qread_login');
        } else {
          // TODO(asm 0xf75494): the original pulls the shelf of the bound backend; that API is not ported.
          Toast.show('当前版本暂不支持从后端导入书架');
        }
        return true;
      case 'viewlog':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LogPage()));
        return true;
    }
    return false;
  }

  /// 添加配置 (0xf771c8 shows `导入成功` / `导入失败:`): reads the text from a file, a link or a scanned code and imports it into the
  /// list its fields belong to. TODO(asm 0xf771c8): the original's type detection is not recovered; this one goes by field names.
  static Future<void> importConfig(BuildContext context, String type) async {
    String? text;
    try {
      switch (type) {
        case 'file':
          text = await SourceImport.pickFileText();
        case 'url':
          final url = await showInputDialog(context, title: '网络导入', hint: '请输入配置文件链接');
          if (url == null || url.trim().isEmpty) return;
          text = await _download(url.trim());
        default:
          final code = context.mounted ? await SourceImport.scan(context) : null;
          if (code == null || code.trim().isEmpty) return;
          final c = code.trim();
          text = c.startsWith('http://') || c.startsWith('https://') ? await _download(c) : c;
      }
      if (text == null || text.trim().isEmpty) return;
      final n = await importText(text);
      Toast.show('导入成功${n > 0 ? '（$n）' : ''}');
    } catch (e) {
      Toast.show('导入失败:$e!', iserror: true);
    }
  }

  static Future<String> _download(String url) async {
    final r = await Dio().get<String>(url, options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  /// Imports [text] into the list its entries belong to; returns the number of imported entries. Throws [FormatException] when the
  /// text is not a known configuration.
  static Future<int> importText(String text) async {
    final v = jsonDecode(text.trim());
    final first = v is List ? (v.isEmpty ? null : v.first) : v;
    if (first is! Map) throw const FormatException('无法识别的配置');
    bool has(String k) => first.containsKey(k);
    if (has('bookSourceUrl')) return (await Sources.importJson(text)).added;
    if (has('sourceUrl') && (has('sourceName') || has('ruleArticles'))) return (await RssSources.importJson(text)).added;
    if (has('pattern') && has('replacement')) return Replaces.importJson(text);
    if (has('pattern') && (has('dayColor') || has('nightColor') || has('dayBgColor'))) return Highlights.importJson(text);
    if (has('rule') && has('name')) return Txtrule.importJson(text);
    if (has('tp') || has('engineId') || has('narrationEngineId')) return Tts.importJson(text);
    if (has('components')) return Exploration.importJson(text);
    throw const FormatException('无法识别的配置');
  }
}

/// 查看日志: the messages the app showed (`Toast.log`), newest first.
class LogPage extends StatelessWidget {
  const LogPage({super.key});
  @override
  Widget build(BuildContext context) {
    final lines = Toast.log.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('查看日志')),
      body: lines.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.separated(
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(dense: true, title: SelectableText(lines[i])),
            ),
    );
  }
}
