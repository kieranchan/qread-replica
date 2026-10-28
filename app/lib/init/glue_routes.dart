// init/glue_routes.dart — named routes that sit between areas (lead-owned): pages of one area call them, the implementation lives
// in another area or needs pieces of several.
//   source_login / source_variable (argument: source url)  -> the sources area's login / variable dialogs (时光源 login: the page's
//                                                            getloginurl() / login(), pages/source/sg_login.dart)
//   config_import ({type: file|url|qr})                    -> 添加配置: replace rules, TTS engines, TXT rules, highlight rules,
//                                                            book / RSS sources, exploration templates; detected by their fields
//   qread_import                                           -> 导入后端: upload txt / epub to the bound backend (bind it first)
//   viewlog                                                -> the in-app message log
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/replace.dart';
import '../data/rss.dart';
import '../data/source.dart';
import '../data/tts.dart';
import '../data/txtrule.dart';
import '../common/nav.dart';
import '../pages/source/login_dialog.dart';
import '../pages/source/sg_login.dart';
import '../pages/source/source_setting.dart';
import '../qread/qread.dart';
import '../qread/qread_jobs.dart';
import '../util/source/source.dart';
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
        if (!context.mounted) return true;
        if (name == 'source_login' && BaseSource.isTimeSource(raw)) {
          // 时光源: the page's getloginurl() / login() (pages/source/sg_login.dart, original 0xe5b940)
          await showTimeSourceLogin(context, BaseSource.fromJson(raw));
          return true;
        }
        final source = BookSource.fromJson(raw);
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
          // 导入后端 (0xf75494 → 0xf77e50): local txt / epub files uploaded to the backend's shelf (qread/qread_jobs.dart)
          await QreadImport.run();
        }
        return true;
      case 'viewlog':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LogPage()));
        return true;
    }
    return false;
  }

  /// 添加配置 (shelf menu 0xf75494: file `json`, link, or scanned code — an `http` code is downloaded): imports the text into the
  /// list it belongs to ([importText]).
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

  /// The original's importer (0xe6af58) decides by substrings of the raw text, in this order:
  ///   `bookSourceUrl` and `bookSourceName` -> book sources; `sourceUrl"` or `sourceUrl'` -> RSS sources;
  ///   `isRegex"` or `isRegex'` -> replace rules; `name` and `html` -> TTS engines; `name` and `rule` -> TXT TOC rules;
  ///   anything else throws `未知的文件格式`.
  /// Returns the number of imported entries.
  static Future<int> importText(String text) async {
    bool has(String s) => text.contains(s);
    if (has('bookSourceUrl') && has('bookSourceName')) return (await Sources.importJson(text)).added;
    if (has('sourceUrl"') || has("sourceUrl'")) return (await RssSources.importJson(text)).added;
    if (has('isRegex"') || has("isRegex'")) return Replaces.importJson(text);
    if (has('name') && has('html')) return Tts.importJson(text);
    if (has('name') && has('rule')) return Txtrule.importJson(text);
    throw const FormatException('未知的文件格式');
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
