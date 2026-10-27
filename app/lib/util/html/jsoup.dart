// util/html/jsoup.dart - jsoup-compatible read helpers over package:html (text(), ownText(), textNodes(), outerHtml ...).
// Legado's `AnalyzeByJSoup` relies on jsoup semantics (whitespace normalisation, block elements add a space); the rule results
// depend on them, so they are reproduced here.
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Parses [source] like `Jsoup.parse` (always a full document).
dom.Document parseHtml(String source) => html_parser.parse(source);

const Set<String> _blockTags = {
  'html', 'head', 'body', 'frameset', 'script', 'noscript', 'style', 'meta', 'link', 'title', 'frame', 'noframes', 'section',
  'nav', 'aside', 'hgroup', 'header', 'footer', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'pre', 'div', 'blockquote',
  'hr', 'address', 'figure', 'figcaption', 'form', 'fieldset', 'ins', 'del', 'dl', 'dt', 'dd', 'li', 'table', 'caption',
  'thead', 'tfoot', 'tbody', 'colgroup', 'col', 'tr', 'th', 'td', 'video', 'audio', 'canvas', 'details', 'menu', 'plaintext',
  'template', 'article', 'main', 'svg', 'math', 'center', 'dir', 'applet', 'marquee', 'listing', 'option', 'optgroup',
};

bool isBlockTag(String? tag) => tag != null && _blockTags.contains(tag.toLowerCase());

bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0c || c == 0x0d;
bool _isActuallyWs(int c) => _isWs(c) || c == 0xa0;

/// jsoup `StringUtil.normaliseWhitespace`.
String normaliseWhitespace(String s) {
  final sb = StringBuffer();
  _appendNormalised(sb, s, false);
  return sb.toString();
}

void _appendNormalised(StringBuffer sb, String text, bool stripLeading) {
  var lastWasWhite = false;
  var reachedNonWhite = false;
  for (final c in text.runes) {
    if (_isActuallyWs(c)) {
      if ((stripLeading && !reachedNonWhite) || lastWasWhite) continue;
      sb.write(' ');
      lastWasWhite = true;
    } else {
      sb.writeCharCode(c);
      lastWasWhite = false;
      reachedNonWhite = true;
    }
  }
}

class _Acc {
  final StringBuffer sb = StringBuffer();
  int _len = 0;
  int _last = 0;
  bool get isEmpty => _len == 0;
  bool get lastIsWs => _len > 0 && _isActuallyWs(_last);
  void add(String s) {
    if (s.isEmpty) return;
    sb.write(s);
    _len += s.length;
    _last = s.codeUnitAt(s.length - 1);
  }

  @override
  String toString() => sb.toString();
}

bool _preserveWs(dom.Node? n) {
  var el = n;
  var depth = 0;
  while (el is dom.Element && depth < 6) {
    final t = el.localName;
    if (t == 'pre' || t == 'textarea') return true;
    el = el.parent;
    depth++;
  }
  return false;
}

bool _isDataText(dom.Text t) {
  final p = t.parent;
  return p is dom.Element && (p.localName == 'script' || p.localName == 'style');
}

void _textVisit(dom.Node node, _Acc acc) {
  if (node is dom.Text) {
    if (_isDataText(node)) return;
    if (_preserveWs(node.parent)) {
      acc.add(node.data);
    } else {
      final sb = StringBuffer();
      _appendNormalised(sb, node.data, acc.isEmpty || acc.lastIsWs);
      acc.add(sb.toString());
    }
    return;
  }
  if (node is dom.Element) {
    if (!acc.isEmpty && (isBlockTag(node.localName) || node.localName == 'br') && !acc.lastIsWs) acc.add(' ');
    for (final c in node.nodes) {
      _textVisit(c, acc);
    }
    if (isBlockTag(node.localName)) {
      final nextNode = _nextSibling(node);
      if (nextNode is dom.Text && !acc.lastIsWs) acc.add(' ');
    }
  }
}

dom.Node? _nextSibling(dom.Node n) {
  final p = n.parentNode;
  if (p == null) return null;
  final i = p.nodes.indexOf(n);
  if (i < 0 || i + 1 >= p.nodes.length) return null;
  return p.nodes[i + 1];
}

/// jsoup `Element.text()` (also accepts a Document).
String jText(dom.Node node) {
  final acc = _Acc();
  if (node is dom.Document || node is dom.DocumentFragment) {
    for (final c in node.nodes) {
      _textVisit(c, acc);
    }
  } else {
    _textVisit(node, acc);
  }
  return acc.toString().trim();
}

/// jsoup `Element.ownText()`.
String jOwnText(dom.Node node) {
  final acc = _Acc();
  for (final c in node.nodes) {
    if (c is dom.Text) {
      if (_isDataText(c)) continue;
      if (_preserveWs(c.parent)) {
        acc.add(c.data);
      } else {
        final sb = StringBuffer();
        _appendNormalised(sb, c.data, acc.isEmpty || acc.lastIsWs);
        acc.add(sb.toString());
      }
    } else if (c is dom.Element && c.localName == 'br' && !acc.lastIsWs) {
      acc.add(' ');
    }
  }
  return acc.toString().trim();
}

/// jsoup `Element.textNodes()` mapped to `TextNode.text()` (normalised whitespace).
List<String> jTextNodes(dom.Node node) {
  final out = <String>[];
  for (final c in node.nodes) {
    if (c is dom.Text) out.add(normaliseWhitespace(c.data));
  }
  return out;
}

/// jsoup `Element.data()`: the contents of script/style (and comments-as-data) children.
String jData(dom.Node node) {
  final sb = StringBuffer();
  for (final c in node.nodes) {
    if (c is dom.Text && _isDataText(c)) sb.write(c.data);
  }
  return sb.toString();
}

/// jsoup `wholeText()`.
String jWholeText(dom.Node node) {
  final sb = StringBuffer();
  void walk(dom.Node n) {
    if (n is dom.Text) {
      sb.write(n.data);
    } else {
      for (final c in n.nodes) {
        if (c is dom.Element && c.localName == 'br') {
          sb.write('\n');
        } else {
          walk(c);
        }
      }
    }
  }

  walk(node);
  return sb.toString();
}

String jOuterHtml(dom.Node node) {
  if (node is dom.Element) return node.outerHtml;
  if (node is dom.Document) return node.outerHtml;
  if (node is dom.Text) return node.data;
  return node.toString();
}

String jInnerHtml(dom.Node node) {
  if (node is dom.Element) return node.innerHtml;
  final sb = StringBuffer();
  for (final c in node.nodes) {
    sb.write(jOuterHtml(c));
  }
  return sb.toString();
}

/// Attribute value (jsoup `attr`): empty string when missing; keys are case-insensitive.
String jAttr(dom.Element e, String name) {
  final v = e.attributes[name];
  if (v != null) return v;
  final lower = name.toLowerCase();
  for (final entry in e.attributes.entries) {
    if (entry.key.toString().toLowerCase() == lower) return entry.value;
  }
  return '';
}

bool jHasAttr(dom.Element e, String name) {
  final lower = name.toLowerCase();
  for (final k in e.attributes.keys) {
    if (k.toString().toLowerCase() == lower) return true;
  }
  return false;
}

/// Child elements of an Element or Document.
List<dom.Element> jChildren(dom.Node node) => node.nodes.whereType<dom.Element>().toList();

/// The element itself plus all descendant elements in document order (jsoup `Collector.collect` order).
Iterable<dom.Element> jSelfAndDescendants(dom.Node node) sync* {
  if (node is dom.Element) yield node;
  for (final c in node.nodes) {
    if (c is dom.Element) yield* jSelfAndDescendants(c);
  }
}

int jSiblingIndex(dom.Element e) {
  final p = e.parentNode;
  if (p == null) return 0;
  var i = 0;
  for (final n in p.nodes) {
    if (identical(n, e)) return i;
    if (n is dom.Element) i++;
  }
  return i;
}

bool jHasClass(dom.Element e, String cls) {
  final c = e.className;
  if (c.isEmpty) return false;
  final want = cls.toLowerCase();
  for (final p in c.split(RegExp(r'\s+'))) {
    if (p.toLowerCase() == want) return true;
  }
  return false;
}

List<dom.Element> getElementsByClass(dom.Node root, String cls) =>
    jSelfAndDescendants(root).where((e) => jHasClass(e, cls)).toList();

List<dom.Element> getElementsByTag(dom.Node root, String tag) {
  final t = tag.toLowerCase();
  return jSelfAndDescendants(root).where((e) => (e.localName ?? '').toLowerCase() == t).toList();
}

List<dom.Element> getElementsById(dom.Node root, String id) =>
    jSelfAndDescendants(root).where((e) => e.id == id).toList();

/// jsoup `getElementsContainingOwnText`.
List<dom.Element> getElementsContainingOwnText(dom.Node root, String text) {
  final t = text.toLowerCase();
  return jSelfAndDescendants(root).where((e) => jOwnText(e).toLowerCase().contains(t)).toList();
}
