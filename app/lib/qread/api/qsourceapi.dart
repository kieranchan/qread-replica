// qread/api/qsourceapi.dart — book-source calls of the bound 轻阅读 backend (all through `Qread.post`, i.e. the user's own server).
//
// Original call sites (request bodies are only partly visible in the digests; the shapes below follow the visible keys):
//   /getBookSourcesPage 0xf1b4bc (`oldmd5`, query `&st=1`; reply data/page/md5)   /getBookSourcesNew 0xf1ba10 (`md5`, `page`)
//   /getbookSourcejson 0xf83c84   /getbookSources 0x10c1134 (`id`)   /editbookSources 0xf96eb4 (`id`, `json`)
//   /saveBookSourcesv2 0xe75664 (`source`, `urls`, `group`)   /delbookSource 0xf8cf0c   /delbookSources 0xf8b7a0
//   /startbookSources 0xf8aac4  /stopbookSources 0xf8a93c  /stopbookSource 0xf8e3dc (`id`, `st`)
//   /startbookSourceExplores 0xf89bc4  /stopbookSourceExplores 0xf89a3c  /editsourcegroup 0xf871bc (query `&st=&group=`)
//   /setVariable 0xf8d4f8  /getVariable 0xf8d2a4  /cleancookies 0xf9552c  /cleancaches 0xf96674
//   /searchBook 0xf873d0 (`bookSourceUrl`, `key`, `page`)  /exploreBook 0x1058564 (`bookSourceUrl`, `ruleFindUrl`, `page`)
import 'dart:convert';

import '../../data/qsource.dart';
import '../../models/source.dart';
import '../qread.dart';

/// One page of the backend's source list (`SourcesJson`).
class SourcesJson {
  final List<Map<String, dynamic>> sources;
  final int page;
  final String md5;
  const SourcesJson(this.sources, this.page, this.md5);
}

abstract class QSourceApi {
  static Map<String, dynamic> _map(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) return Map<String, dynamic>.from(jsonDecode(v) as Map);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(Object? v) {
    if (v is String && v.trim().startsWith('[')) v = jsonDecode(v);
    if (v is Map && v['list'] is List) v = v['list'];
    return [for (final e in (v is List ? v : const [])) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// `/getBookSourcesNew`: one page of the list (page numbers start at 1).
  static Future<SourcesJson> page(int page, {String md5 = ''}) async {
    final data = await Qread.post('/getBookSourcesNew', {'md5': md5, 'page': page});
    final m = data is Map ? data : const {};
    return SourcesJson(_list(data), int.tryParse('${m['page'] ?? 0}') ?? 0, '${m['md5'] ?? ''}');
  }

  /// Loads every page and replaces the local cache (`sourcedata`). Each source is marked `isqread`.
  static Future<List<Source>> refresh() async {
    final all = <Map<String, dynamic>>[];
    var md5 = '';
    for (var p = 1; p <= 200; p++) {
      final r = await page(p, md5: QSources.md5);
      if (r.md5.isNotEmpty) md5 = r.md5;
      all.addAll(r.sources);
      // TODO(asm 0xf1b4bc): the paging contract (`page` = total pages or next page) is inferred
      if (r.sources.isEmpty || r.page <= p) break;
    }
    final list = [for (final m in all) Source.fromJson({...m, 'isqread': true})];
    await QSources.replace(SourceMsg(list, md5));
    return list;
  }

  /// `/getbookSourcejson`: the full Legado JSON of one backend source.
  static Future<Map<String, dynamic>> sourceJson(String url) async => _map(await Qread.post('/getbookSourcejson', {'id': url}));

  /// `/editbookSources`: saves one edited source (`id` = old url).
  static Future<void> save(String oldUrl, Map<String, dynamic> json) async {
    await Qread.post('/editbookSources', {'id': oldUrl, 'json': jsonEncode(json)});
  }

  /// `/saveBookSourcesv2`: uploads Legado sources (import with 轻阅读解析).
  static Future<void> saveAll(List<Map<String, dynamic>> sources, {String group = ''}) async {
    await Qread.post('/saveBookSourcesv2', {'source': jsonEncode(sources), 'urls': [for (final s in sources) s['bookSourceUrl']], 'group': group});
  }

  static Future<void> delete(Iterable<String> urls) async => Qread.post('/delbookSources', {'id': urls.toList()});

  static Future<void> setEnabled(Iterable<String> urls, bool on) async =>
      Qread.post(on ? '/startbookSources' : '/stopbookSources', {'id': urls.toList()});

  static Future<void> setEnabledExplore(Iterable<String> urls, bool on) async =>
      Qread.post(on ? '/startbookSourceExplores' : '/stopbookSourceExplores', {'id': urls.toList()});

  /// `/editsourcegroup`: [st] 1 adds the group, 0 removes it.
  static Future<void> editGroup(Iterable<String> urls, String group, {int st = 1}) async =>
      Qread.post('/editsourcegroup', {'id': urls.toList()}, '&st=$st&group=${Uri.encodeQueryComponent(group)}');

  static Future<void> setVariable(String url, String variable) async => Qread.post('/setVariable', {'id': url, 'variable': variable});

  static Future<String> getVariable(String url) async => '${await Qread.post('/getVariable', {'id': url}) ?? ''}';

  static Future<void> cleanCookies(String url) async => Qread.post('/cleancookies', {'id': url});

  static Future<void> cleanCaches(String url) async => Qread.post('/cleancaches', {'id': url});

  static Future<List<Map<String, dynamic>>> search(String sourceUrl, String key, {int page = 1}) async =>
      _list(await Qread.post('/searchBook', {'bookSourceUrl': sourceUrl, 'key': key, 'page': page}));

  static Future<List<Map<String, dynamic>>> explore(String sourceUrl, String ruleFindUrl, {int page = 1}) async =>
      _list(await Qread.post('/exploreBook', {'bookSourceUrl': sourceUrl, 'ruleFindUrl': ruleFindUrl, 'page': page}));
}
