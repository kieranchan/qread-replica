// read/epub/epub_html.dart — chapter HTML (EPUB / MOBI) -> [ChapterContent] (text paragraphs with inline styles + images).
//
// The original renders EPUB through epub.js in a WebView (`util/epub/*`); this port converts the XHTML to the same block model
// the TXT reader uses so that one layout engine serves every book format. Supported: paragraphs / headings / list items /
// blockquotes / table cells / `<br>` as paragraph breaks, `b i u s sup sub code a`, inline `style` (font-weight, font-style,
// text-decoration, text-align), `<img>` / SVG `<image>` as image blocks, element ids as anchors, footnote links
// (`epub:type="noteref"`). Not supported: CSS stylesheets and class rules, floats, tables as grids, inline images inside a
// paragraph (they split the paragraph), MathML.
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../model/line.dart';
import '../model/page.dart';
import '../util/chapter_content.dart';

/// Maps an image reference found in the HTML (already resolved to a path inside the archive) to a path the UI can load,
/// or null to drop the image.
typedef EpubImageResolver = String? Function(String archivePath);

class EpubHtml {
  /// [archiveDir] is the directory of the HTML file inside the archive (`OEBPS/text`), used to resolve relative image paths.
  static ChapterContent toContent(
    String html, {
    String archiveDir = '',
    EpubImageResolver? resolveImage,
    String? fromAnchor,
    String? toAnchor,
  }) {
    final doc = html_parser.parse(_expandSelfClosing(html));
    final b = _Builder(archiveDir, resolveImage);
    final body = doc.body ?? doc.documentElement;
    if (body == null) return ChapterContent.empty;
    b.fromAnchor = fromAnchor ?? '';
    b.toAnchor = toAnchor ?? '';
    b.skipping = b.fromAnchor.isNotEmpty;
    b.walk(body);
    return b.finish();
  }

  /// First `<title>` / heading text (for chapters without a TOC entry). Cheap regex on the head of the file.
  static String? guessTitle(String html) {
    final head = html.length > 6000 ? html.substring(0, 6000) : html;
    for (final re in [
      RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', caseSensitive: false, dotAll: true),
      RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true),
    ]) {
      final m = re.firstMatch(head);
      if (m != null) {
        final t = m.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty) return _unescape(t);
      }
    }
    return null;
  }

  static String _unescape(String s) => html_parser.parseFragment(s).text ?? s;

  /// XHTML allows `<a id="x"/>`, `<div/>`; the HTML parser would treat them as open tags and swallow what follows.
  static String _expandSelfClosing(String html) => html.replaceAllMapped(
        RegExp(r'<(a|span|div|p|b|i|em|strong|section|h[1-6]|li|ul|ol|td|tr|table|font|u|s|sup|sub|small|big|blockquote|center)(\s[^<>]*?)?\s*/>', caseSensitive: false),
        (m) => '<${m[1]}${m[2] ?? ''}></${m[1]}>',
      );
}

const _blockTags = {
  'p', 'div', 'section', 'article', 'aside', 'header', 'footer', 'main', 'nav', 'blockquote', 'ul', 'ol', 'li', 'dl', 'dt', 'dd',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'figure', 'figcaption', 'pre', 'hr',
  'address', 'center', 'body', 'br',
};
const _skipTags = {'script', 'style', 'head', 'title', 'meta', 'link', 'noscript', 'template'};

class _Ctx {
  final Set<String> tokens;
  final String href;
  final bool noteref;
  final bool heading;
  final bool pre;
  const _Ctx(this.tokens, this.href, this.noteref, this.heading, this.pre);
}

class _Builder {
  final String archiveDir;
  final EpubImageResolver? resolveImage;
  _Builder(this.archiveDir, this.resolveImage);

  String fromAnchor = '';
  String toAnchor = '';
  bool skipping = false;
  bool done = false;

  final StringBuffer _text = StringBuffer();
  int _textLen = 0;
  final List<CalcuPages> _blocks = [];

  List<CLine> _runs = [];
  final StringBuffer _para = StringBuffer();
  String _pendingId = '';

  ChapterContent finish() {
    _flush();
    return ChapterContent(_text.toString(), _blocks);
  }

  void walk(Node node, [_Ctx? parent]) {
    if (done) return;
    final ctx = parent ?? const _Ctx({}, '', false, false, false);
    if (node is Text) {
      if (!skipping) _addText(node.data, ctx);
      return;
    }
    if (node is! Element) {
      for (final c in node.nodes) {
        walk(c, ctx);
      }
      return;
    }
    final tag = (node.localName ?? '').toLowerCase();
    if (_skipTags.contains(tag)) return;
    if (_hidden(node)) return;

    final id = _attr(node, 'id');
    if (id.isNotEmpty) {
      if (skipping && id == fromAnchor) skipping = false;
      if (!skipping && toAnchor.isNotEmpty && id == toAnchor) {
        _flush();
        done = true;
        return;
      }
      if (!skipping) _pendingId = _pendingId.isEmpty ? id : _pendingId;
    }

    if (tag == 'img' || tag == 'image') {
      if (!skipping) _addImage(node);
      return;
    }
    if (tag == 'svg') {
      for (final c in node.nodes) {
        walk(c, ctx);
      }
      return;
    }

    final isBlock = _blockTags.contains(tag);
    if (tag == 'br' || tag == 'hr') {
      _flush();
      return;
    }
    if (isBlock) _flush();

    final tokens = {...ctx.tokens};
    var href = ctx.href;
    var noteref = ctx.noteref;
    var heading = ctx.heading;
    var pre = ctx.pre;
    switch (tag) {
      case 'b':
      case 'strong':
        tokens.add(CLineStyle.bold);
      case 'i':
      case 'em':
      case 'cite':
      case 'dfn':
        tokens.add(CLineStyle.italic);
      case 'u':
      case 'ins':
        tokens.add(CLineStyle.underline);
      case 's':
      case 'strike':
      case 'del':
        tokens.add(CLineStyle.strike);
      case 'sup':
        tokens.add(CLineStyle.sup);
      case 'sub':
        tokens.add(CLineStyle.sub);
      case 'code':
      case 'tt':
      case 'kbd':
      case 'samp':
        tokens.add(CLineStyle.code);
      case 'pre':
        pre = true;
        tokens.add(CLineStyle.code);
      case 'center':
        tokens.add(CLineStyle.center);
      case 'h1':
        tokens.add(CLineStyle.h1);
        heading = true;
      case 'h2':
        tokens.add(CLineStyle.h2);
        heading = true;
      case 'h3':
        tokens.add(CLineStyle.h3);
        heading = true;
      case 'h4':
      case 'h5':
      case 'h6':
        tokens.add(CLineStyle.bold);
        heading = true;
      case 'a':
        final h = _attr(node, 'href');
        if (h.isNotEmpty) {
          href = h;
          tokens.add(CLineStyle.link);
          final type = '${_attr(node, 'epub:type')} ${_attr(node, 'role')}'.toLowerCase();
          if (type.contains('noteref')) noteref = true;
        }
    }
    _applyInlineStyle(node, tokens);

    final next = _Ctx(tokens, href, noteref, heading, pre);
    for (final c in node.nodes) {
      walk(c, next);
    }
    if (isBlock) _flush();
  }

  // ---- inline style attribute ------------------------------------------------------------------------------------------
  void _applyInlineStyle(Element e, Set<String> tokens) {
    final style = _attr(e, 'style').toLowerCase();
    if (style.isNotEmpty) {
      final w = RegExp(r'font-weight\s*:\s*([a-z0-9]+)').firstMatch(style)?.group(1);
      if (w == 'bold' || w == 'bolder' || ((int.tryParse(w ?? '') ?? 0) >= 600)) tokens.add(CLineStyle.bold);
      if (RegExp(r'font-style\s*:\s*italic').hasMatch(style)) tokens.add(CLineStyle.italic);
      if (RegExp(r'text-decoration[^;]*underline').hasMatch(style)) tokens.add(CLineStyle.underline);
      if (RegExp(r'text-decoration[^;]*line-through').hasMatch(style)) tokens.add(CLineStyle.strike);
      final align = RegExp(r'text-align\s*:\s*([a-z]+)').firstMatch(style)?.group(1);
      if (align == 'center') tokens.add(CLineStyle.center);
      if (align == 'right') tokens.add(CLineStyle.right);
    }
    final a = _attr(e, 'align').toLowerCase();
    if (a == 'center') tokens.add(CLineStyle.center);
    if (a == 'right') tokens.add(CLineStyle.right);
  }

  bool _hidden(Element e) {
    if (e.attributes.containsKey('hidden')) return true;
    final style = _attr(e, 'style').toLowerCase().replaceAll(' ', '');
    return style.contains('display:none');
  }

  // ---- text -------------------------------------------------------------------------------------------------------------
  void _addText(String raw, _Ctx ctx) {
    var s = raw;
    if (ctx.pre) {
      // keep line breaks: every line is its own paragraph
      final lines = s.replaceAll('\r\n', '\n').split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) _flush();
        _append(lines[i], ctx);
      }
      return;
    }
    // Whitespace that contains a line break is source wrapping: mark it, [_stripCjkSpaces] drops it between CJK characters
    // and turns it into one space otherwise. Plain spaces are real and are only collapsed.
    s = s.replaceAll(RegExp(r'[ \t\u00a0]*[\r\n][\s\u00a0]*'), _wrap).replaceAll(RegExp(r'[ \t\u00a0]+'), ' ');
    if (_para.isEmpty) s = s.replaceFirst(RegExp(r'^[ \u0001]+'), '');
    if (s.isEmpty) return;
    _append(s, ctx);
  }

  void _append(String s, _Ctx ctx) {
    if (s.isEmpty) return;
    final style = (ctx.tokens.toList()..sort()).join(' ');
    final run = CLine(
      str: s,
      style: style,
      href: ctx.href,
      noteref: ctx.noteref,
      ish: ctx.heading,
      id: _pendingId,
    );
    _pendingId = '';
    if (_runs.isNotEmpty) {
      final last = _runs.last;
      if (last.style == run.style && last.href == run.href && last.noteref == run.noteref && last.ish == run.ish && run.id.isEmpty) {
        last.str += s;
        _para.write(s);
        return;
      }
    }
    _runs.add(run);
    _para.write(s);
  }

  // ---- blocks -----------------------------------------------------------------------------------------------------------
  void _flush() {
    if (_runs.isEmpty) {
      _para.clear();
      return;
    }
    // trim, and drop the spaces HTML source wrapping leaves between CJK characters
    final runs = _runs;
    _runs = [];
    _para.clear();
    _stripCjkSpaces(runs);
    runs.first.str = runs.first.str.trimLeft();
    runs.last.str = runs.last.str.trimRight();
    runs.removeWhere((r) => r.str.isEmpty && r.id.isEmpty);
    if (runs.isEmpty || runs.every((r) => r.str.isEmpty)) {
      // keep a pending anchor for the next block
      for (final r in runs) {
        if (r.id.isNotEmpty && _pendingId.isEmpty) _pendingId = r.id;
      }
      return;
    }
    if (_blocks.isNotEmpty) {
      _text.write('\n');
      _textLen += 1;
    }
    var pos = _textLen;
    var first = true;
    for (final r in runs) {
      r.start = pos;
      pos += r.str.length;
      r.end = pos;
      r.isfirst = first;
      first = false;
      _text.write(r.str);
    }
    _textLen = pos;
    _blocks.add(CalcuPages.text(runs));
  }

  static const String _wrap = '\u0001';
  static final RegExp _cjk = RegExp(r'[⺀-鿿＀-￯　-〿]');

  void _stripCjkSpaces(List<CLine> runs) {
    for (var i = 0; i < runs.length; i++) {
      final s = runs[i].str;
      if (!s.contains(_wrap)) continue;
      final sb = StringBuffer();
      for (var k = 0; k < s.length; k++) {
        final ch = s[k];
        if (ch == _wrap) {
          final prev = k > 0 ? s[k - 1] : (i > 0 && runs[i - 1].str.isNotEmpty ? runs[i - 1].str[runs[i - 1].str.length - 1] : '');
          final next = k + 1 < s.length ? s[k + 1] : (i + 1 < runs.length && runs[i + 1].str.isNotEmpty ? runs[i + 1].str[0] : '');
          if ((prev.isNotEmpty && _cjk.hasMatch(prev)) || (next.isNotEmpty && _cjk.hasMatch(next))) continue;
          sb.write(' ');
          continue;
        }
        sb.write(ch);
      }
      runs[i].str = sb.toString();
    }
  }

  void _addImage(Element e) {
    var src = _attr(e, 'src');
    if (src.isEmpty) src = _attr(e, 'xlink:href');
    if (src.isEmpty) src = _attr(e, 'href');
    if (src.isEmpty) return;
    final path = _resolve(src);
    final local = resolveImage == null ? path : resolveImage!(path);
    if (local == null) return;
    _flush();
    final run = CLine(
      type: CLineType.image,
      style: CLineStyle.image,
      href: local,
      start: _textLen,
      end: _textLen,
      isfirst: true,
      id: _pendingId,
    );
    _pendingId = '';
    _blocks.add(CalcuPages.image(run));
  }

  /// `data:` URIs stay as they are; everything else is joined to [archiveDir], `..`-normalised and percent-decoded.
  String _resolve(String src) {
    if (src.startsWith('data:')) return src;
    var s = src.split('#').first.split('?').first;
    try {
      s = Uri.decodeFull(s);
    } catch (_) {}
    return normalizeArchivePath(s.startsWith('/') ? s.substring(1) : (archiveDir.isEmpty ? s : '$archiveDir/$s'));
  }

  /// Collapses `a/./b/../c` inside an archive path.
  static String normalizeArchivePath(String path) {
    final out = <String>[];
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(part);
    }
    return out.join('/');
  }

  static String _attr(Element e, String name) {
    final direct = e.attributes[name];
    if (direct != null) return direct;
    for (final entry in e.attributes.entries) {
      final k = entry.key.toString().toLowerCase();
      if (k == name || k.endsWith(' $name') || k.endsWith(':$name')) return entry.value;
    }
    return '';
  }
}

/// Path helper shared with `EpubFile`.
String normalizeArchivePath(String path) => _Builder.normalizeArchivePath(path);
