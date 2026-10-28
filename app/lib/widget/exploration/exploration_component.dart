// widget/exploration/exploration_component.dart — what the exploration components share: the component types (enum
// `ComponentType` of models/exploration_template.dart: 7 values), the config keys read by the widgets (`title`,
// `bookSourceUrl`, `isQRead`, `exploreUrl`, `categories` [{title, exploreUrl}], `count`, `countPerCategory`, `itemWidth`,
// `gap`), the book loader and the section frame.
//
// TODO(asm 0x647e58): `fromJson` finds the enum value by a string compare with `json['type']`; the 7 `ComponentType` objects in
// the pool keep only their index (objs.txt, names stripped), so the stored strings are unknown: the replica writes the Dart enum
// name and also accepts the index.
import 'package:flutter/material.dart';

import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/exploration_template.dart';
import '../../models/source.dart';
import '../../pages/book/book_detail_page.dart';
import '../../pages/search/book_search_service.dart';
import '../image/cached_cover_image.dart';

enum ComponentType {
  recommendCard('推荐卡片', 3),
  grid('宫格', 6),
  horizontalScroll('左右滑动', 10),
  ranking('排行榜', 10),
  networkRanking('网络排行榜', 10),
  multiCategoryRanking('多分类排行榜', 5),
  staggeredWaterfall('错位瀑布流', 10);

  final String label;
  final int defaultCount;
  const ComponentType(this.label, this.defaultCount);

  static ComponentType of(Object? v) {
    if (v is int && v >= 0 && v < values.length) return values[v];
    final s = '$v';
    for (final t in values) {
      if (t.name == s || 'ComponentType.${t.name}' == s || t.label == s) return t;
    }
    final i = int.tryParse(s);
    return i != null && i >= 0 && i < values.length ? values[i] : ComponentType.grid;
  }
}

/// Typed view of a component's config map.
class ComponentConfig {
  final Map<String, dynamic> map;
  ComponentConfig(this.map);

  String get title => '${map['title'] ?? ''}';
  String get sourceUrl => '${map['bookSourceUrl'] ?? ''}';
  String get exploreUrl => '${map['exploreUrl'] ?? ''}';
  int get count => int.tryParse('${map['count'] ?? ''}') ?? 0;
  int get countPerCategory => int.tryParse('${map['countPerCategory'] ?? ''}') ?? 5;
  double get itemWidth => double.tryParse('${map['itemWidth'] ?? ''}') ?? 90;
  double get gap => double.tryParse('${map['gap'] ?? ''}') ?? 10;

  /// `categories`: [{title, exploreUrl}] (multi-category ranking).
  List<Map<String, String>> get categories => [
        for (final e in (map['categories'] is List ? map['categories'] as List : const []))
          if (e is Map) {'title': '${e['title'] ?? ''}', 'exploreUrl': '${e['exploreUrl'] ?? e['url'] ?? ''}'}
      ];

  Source? get source => Sourcedata.sourceByUrl(sourceUrl);
}

ComponentType typeOf(ExplorationComponent c) => ComponentType.of(c.type_);

/// First page of an explore url, cut to [count].
Future<List<Book>> loadComponentBooks(ComponentConfig cfg, {String? url, int? count}) async {
  final s = cfg.source;
  if (s == null) throw StateError('请选择书源');
  final u = url ?? cfg.exploreUrl;
  if (u.isEmpty) throw StateError('请选择发现项');
  final list = await BookSearchService.instance.explore(s, u, 1);
  final n = count ?? cfg.count;
  return n > 0 && list.length > n ? list.sublist(0, n) : list;
}

void openBook(BuildContext context, Book b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b)));

/// Section frame: title row + child; shows loading / error states of [future].
class ComponentSection extends StatelessWidget {
  final String title;
  final Future<List<Book>> future;
  final Widget Function(BuildContext context, List<Book> books) builder;

  const ComponentSection({super.key, required this.title, required this.future, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        FutureBuilder<List<Book>>(
          future: future,
          builder: (c, s) {
            if (s.hasError) {
              return Padding(padding: const EdgeInsets.all(16), child: Text('${s.error}', style: const TextStyle(color: Colors.grey)));
            }
            if (!s.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            return builder(c, s.data!);
          },
        ),
      ]),
    );
  }
}

/// Cover + title cell used by the grid / scroll / waterfall components.
class CoverCell extends StatelessWidget {
  final Book book;
  final double width;
  final double ratio;

  const CoverCell({super.key, required this.book, required this.width, this.ratio = 4 / 3});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openBook(context, book),
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CachedCoverImage(url: book.coverUrl, title: book.name, author: book.author, width: width, height: width * ratio, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 4),
          Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}

/// Numbered row of the ranking components.
class RankRow extends StatelessWidget {
  final Book book;
  final int rank;

  const RankRow({super.key, required this.book, required this.rank});

  @override
  Widget build(BuildContext context) {
    final color = rank <= 3 ? [Colors.red, Colors.orange, Colors.amber][rank - 1] : Colors.grey;
    return InkWell(
      onTap: () => openBook(context, book),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          SizedBox(width: 28, child: Text('$rank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))),
          CachedCoverImage(url: book.coverUrl, title: book.name, width: 42, height: 56, borderRadius: BorderRadius.circular(4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text([book.author, book.kind].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ]),
      ),
    );
  }
}
