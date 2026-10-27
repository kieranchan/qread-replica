// util/legado/rss_parser_default.dart - the built-in RSS 2.0 / Atom parser used when a source has no `ruleArticles` (Legado
// `RssParserDefault`). Items map to title, link, description (or `content:encoded`/`summary`), pubDate (`published`/`updated`) and an
// image (`enclosure`, `media:thumbnail`, `media:content`, or the first `<img>` of the description).
import 'package:xml/xml.dart';

import '../webbook/model/rss_article.dart';
import '../webbook/util/network_utils.dart';

abstract class RssParserDefault {
  static final RegExp _img = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  static List<RssArticle> parseXML(String xml, String sortName, String sourceUrl) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml.trim());
    } on XmlException {
      return [];
    }
    final items = doc.findAllElements('item').toList();
    final entries = items.isEmpty ? doc.findAllElements('entry').toList() : <XmlElement>[];
    final out = <RssArticle>[];
    var order = 0;
    for (final it in [...items, ...entries]) {
      String? text(String name) {
        final e = it.findElements(name).firstOrNull;
        if (e == null) return null;
        final t = e.innerText.trim();
        return t.isEmpty ? null : t;
      }

      final a = RssArticle(origin: sourceUrl, sort: sortName);
      a.title = text('title') ?? '';
      var link = text('link') ?? '';
      if (link.isEmpty) {
        final l = it.findElements('link').firstOrNull;
        link = l?.getAttribute('href') ?? '';
      }
      a.link = NetworkUtils.getAbsoluteURL(sourceUrl, link);
      a.description = text('description') ?? text('summary') ?? text('content:encoded') ?? text('content');
      a.content = text('content:encoded') ?? text('content');
      a.pubDate = text('pubDate') ?? text('published') ?? text('updated') ?? text('dc:date');
      String? image;
      for (final e in it.descendantElements) {
        final n = e.name.qualified;
        if (n == 'enclosure') {
          final t = e.getAttribute('type') ?? '';
          if (t.startsWith('image') || t.isEmpty) image = e.getAttribute('url');
        } else if (n == 'media:thumbnail' || n == 'media:content') {
          image ??= e.getAttribute('url');
        }
        if (image != null) break;
      }
      image ??= _img.firstMatch(a.description ?? '')?.group(1);
      if (image != null) a.image = NetworkUtils.getAbsoluteURL(sourceUrl, image);
      a.order = order++;
      if (a.title.isNotEmpty) out.add(a);
    }
    return out;
  }
}
