// pages/search/source_filter.dart — not a file of the original: the 筛选 of 时光源 as the search and discovery pages use it.
//
// Original: the single-source search (`_SearchBookPageState`, 0xfdad4c) asks the page's `filter()` once per source choice
// (0xfdb170, reset when the choice changes 0x5fae50) and searches with env `searchone`; its 搜索分类 button (`_showCategoryDialog`
// 0xfdbecc) opens the filter page instead of the category dialog when one source is chosen and the answer starts with `http` /
// `data`. A discovery list (`_SearchPageState`, 0x1058850) asks `findfilter(url)` and shows a filter button (filter_list_alt,
// 0x746e28 / 0x10591a4) for such an answer. The filter page is the source's browser page (its bridge: the choice is kept with
// `cache.set`); when it closes the search cache is cleared (0x1ba52c) and the search / list runs again.
import 'dart:convert';

import '../../api/sourceapi.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../util/source/baswebview.dart';
import '../../util/source/source.dart';
import '../../util/source/time_source_api.dart';
import '../../util/webbook/model/book_source.dart';

abstract class SourceFilter {
  static Map<String, dynamic>? _raw(String sourceUrl) {
    final raw = Sourcedata.byUrl(sourceUrl);
    return BaseSource.isTimeSource(raw) ? raw : null;
  }

  /// Whether [s] is a 时光源 (only those have filters).
  static bool supports(Source s) => _raw(s.bookSourceUrl) != null;

  /// `filter()` of [s] ('' for other sources or when the page fails).
  static Future<String> searchFilter(Source s) async {
    final raw = _raw(s.bookSourceUrl);
    if (raw == null) return '';
    try {
      return (await TimeSourceApi.filter(BookSource.fromJson(Map<String, dynamic>.from(raw)))).trim();
    } catch (_) {
      return '';
    }
  }

  /// `findfilter(url)` of [s] ('' for other sources or when the page fails).
  static Future<String> findFilter(Source s, String url) async {
    final raw = _raw(s.bookSourceUrl);
    if (raw == null) return '';
    try {
      return (await TimeSourceApi.findFilter(BookSource.fromJson(Map<String, dynamic>.from(raw)), url)).trim();
    } catch (_) {
      return '';
    }
  }

  static bool isPage(String filter) => TimeSourceApi.isFilterPage(filter);

  /// The html of a `data:[type][;base64],…` filter (null when it is not one).
  static String? dataHtml(String filter) {
    if (!filter.startsWith('data')) return null;
    final comma = filter.indexOf(',');
    if (comma < 0) return null;
    final head = filter.substring(0, comma);
    final body = filter.substring(comma + 1);
    try {
      if (head.endsWith(';base64')) return utf8.decode(base64Decode(base64.normalize(body.trim())), allowMalformed: true);
      return Uri.decodeComponent(body);
    } catch (_) {
      return null;
    }
  }

  /// Opens [filter] in the source's browser page; afterwards the search results cache is cleared.
  static Future<void> open(Source s, String filter) async {
    final raw = _raw(s.bookSourceUrl);
    if (raw == null) return;
    final src = BaseSource.fromJson(raw);
    final html = dataHtml(filter);
    await SourceUi.openBrowser?.call(html == null
        ? SourceBrowserRequest(url: filter, source: src)
        : SourceBrowserRequest(url: src.bookSourceUrl, html: html, source: src));
    SourceApi.cache.clear();
  }
}
