// widget/exploration/recommend_card_widget.dart — 推荐卡片 (`RecommendCardWidget`): large cards (cover, name, author, intro)
// swiped horizontally.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../image/cached_cover_image.dart';
import 'exploration_component.dart';

class RecommendCardWidget extends StatefulWidget {
  final ComponentConfig config;
  const RecommendCardWidget({super.key, required this.config});

  @override
  State<RecommendCardWidget> createState() => _RecommendCardWidgetState();
}

class _RecommendCardWidgetState extends State<RecommendCardWidget> {
  late final Future<List<Book>> _f = loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : 3);
  final PageController _pc = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComponentSection(
      title: widget.config.title,
      future: _f,
      builder: (c, books) => SizedBox(
        height: 170,
        child: PageView(controller: _pc, children: [
          for (final b in books)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => openBook(context, b),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CachedCoverImage(url: b.coverUrl, title: b.name, width: 100, height: 140, borderRadius: BorderRadius.circular(8)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(b.author, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(b.intro.replaceAll(RegExp('<[^>]+>'), ''), maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
