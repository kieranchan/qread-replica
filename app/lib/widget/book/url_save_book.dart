// widget/book/url_save_book.dart — `urlsaveBook` (0xe69f74 → 0xe6a130): a book page url becomes a book of the shelf's detail page.
// Used by 「网址导入」 (bookshelf 0xf7701c) and `qread:///addToBookshelf?src=` links (0xe6ad38).
//
// The original logs `正在查询书本信息 <url>`, walks the enabled local sources (backend sources, url ending in `@yuedu`, are skipped),
// takes the first whose `bookUrlPattern` (a regex) matches the url (`匹配到 <name>`) and opens BookDetailPage for
// `Book(bookUrl: url, origin: source)`; no match: toast `未检索到能用的书源`.
import 'package:flutter/material.dart';

import '../../data/source.dart';
import '../../util/toast.dart';

/// The first enabled source whose `bookUrlPattern` matches [url] (raw JSON map), or null.
Map<String, dynamic>? sourceForBookUrl(String url) {
  for (final m in Sourcedata.enabledRaw) {
    final su = '${m['bookSourceUrl'] ?? ''}';
    if (su.isEmpty || su.endsWith('@yuedu')) continue;
    final pattern = m['bookUrlPattern'];
    if (pattern is! String || pattern.trim().isEmpty) continue;
    try {
      if (RegExp(pattern).hasMatch(url)) return m;
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// Opens the detail page of [url] with the matching source; false (and the original's toast) when no source matches.
/// [openDetail] shows the page (the shelf passes its BookDetailPage route).
Future<bool> urlSaveBook(BuildContext context, String url, Future<void> Function(String bookUrl, String origin) openDetail) async {
  debugPrint('正在查询书本信息 $url');
  final m = sourceForBookUrl(url);
  if (m == null) {
    Toast.show('未检索到能用的书源', iserror: true);
    return false;
  }
  debugPrint('匹配到 ${m['bookSourceName']}');
  await openDetail(url, '${m['bookSourceUrl']}');
  return true;
}
