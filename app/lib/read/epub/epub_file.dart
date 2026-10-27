// read/epub/epub_file.dart — local EPUB books (original: `abstract class EpubFile`, which unzips the book into `<documents>/epub`
// and scans it for the WebView renderer: 0xedf598 `scan`, 0xf0eb88 `processNodes`, `relPathOf`, `fileName`).
//
// This port reads the zip directly (`archive`): META-INF/container.xml -> OPF (metadata, manifest, spine) -> table of contents
// (EPUB 3 `nav` document, else EPUB 2 `toc.ncx`) -> chapters. A chapter is one spine document, or - when the TOC points to
// several fragments of one document - the part between two TOC anchors. Chapter bodies are converted lazily by [EpubHtml].
//
// BookChapter encoding (the model has no spare fields): `chapterId` = path of the spine document inside the zip, `tag` = start
// anchor ('' = from the top), `baseUrl` = end anchor ('' = to the bottom), `start` = `end` = spine index.
//
// Not supported: DRM / encrypted fonts (the text is still readable), fixed-layout pages (rendered as flowing text), CSS.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/bookchapter.dart';
import '../api/read_file_store.dart';
import '../txt/text_file.dart';
import '../util/chapter_content.dart';
import 'epub_html.dart';

class EpubTocEntry {
  final String title;

  /// Path of the target document inside the zip.
  final String path;
  final String fragment;
  final int depth;
  final bool hasChildren;

  const EpubTocEntry(this.title, this.path, this.fragment, this.depth, this.hasChildren);
}

class EpubSpineItem {
  final String id;
  final String path;
  final String mediaType;
  final bool linear;
  const EpubSpineItem(this.id, this.path, this.mediaType, this.linear);
}

class EpubPackage {
  final String opfPath;
  final String title;
  final String author;
  final String language;
  final String description;
  final String publisher;

  /// Archive path of the cover image, or ''.
  final String coverPath;
  final List<EpubSpineItem> spine;
  final List<EpubTocEntry> toc;

  const EpubPackage({
    required this.opfPath,
    required this.title,
    required this.author,
    required this.language,
    required this.description,
    required this.publisher,
    required this.coverPath,
    required this.spine,
    required this.toc,
  });
}

class EpubParseResult {
  final String name;
  final String author;
  final String intro;
  final String language;

  /// Local path of the extracted cover, or '' (see `coverDir`).
  final String coverFile;
  final List<BookChapter> chapters;

  const EpubParseResult({
    required this.name,
    required this.author,
    required this.intro,
    required this.language,
    required this.coverFile,
    required this.chapters,
  });
}

class EpubException implements Exception {
  final String message;
  const EpubException(this.message);
  @override
  String toString() => message;
}

abstract class EpubFile {
  // ---------------------------------------------------------------- archive helpers

  static ArchiveFile? _find(Archive a, String path) {
    final direct = a.findFile(path);
    if (direct != null && direct.isFile) return direct;
    final lower = path.toLowerCase();
    for (final f in a.files) {
      if (f.isFile && (f.name.toLowerCase() == lower || Uri.decodeFull(f.name).toLowerCase() == lower)) return f;
    }
    return null;
  }

  static Uint8List? _bytes(Archive a, String path) {
    final f = _find(a, path);
    if (f == null) return null;
    return f.readBytes();
  }

  static String? _text(Archive a, String path) {
    final b = _bytes(a, path);
    if (b == null) return null;
    var t = utf8.decode(b, allowMalformed: true);
    if (t.startsWith('﻿')) t = t.substring(1);
    return t;
  }

  static String _dir(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  static String _join(String dir, String href) {
    var h = href.split('?').first;
    try {
      h = Uri.decodeFull(h);
    } catch (_) {}
    return normalizeArchivePath(h.startsWith('/') ? h.substring(1) : (dir.isEmpty ? h : '$dir/$h'));
  }

  // ---------------------------------------------------------------- package

  /// Parses container.xml, the OPF and the TOC of an opened archive (pure; used by the tests).
  static EpubPackage readPackage(Archive archive) {
    final container = _text(archive, 'META-INF/container.xml');
    String? opfPath;
    if (container != null) {
      final doc = XmlDocument.parse(container);
      for (final e in doc.descendantElements) {
        if (e.name.local == 'rootfile') {
          opfPath = e.getAttribute('full-path');
          if (opfPath != null && opfPath.isNotEmpty) break;
        }
      }
    }
    opfPath ??= archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.opf')).map((f) => f.name).firstOrNull;
    if (opfPath == null) throw const EpubException('不是有效的EPUB文件：缺少 container.xml / OPF');
    final opfText = _text(archive, opfPath);
    if (opfText == null) throw EpubException('不是有效的EPUB文件：找不到 $opfPath');
    final opf = XmlDocument.parse(opfText);
    final opfDir = _dir(opfPath);

    String first(String local) {
      for (final e in opf.descendantElements) {
        if (e.name.local == local && e.parent is XmlElement && (e.parent! as XmlElement).name.local == 'metadata') {
          final t = e.innerText.trim();
          if (t.isNotEmpty) return t;
        }
      }
      return '';
    }

    final creators = <String>[
      for (final e in opf.descendantElements)
        if (e.name.local == 'creator' && e.innerText.trim().isNotEmpty) e.innerText.trim(),
    ];

    // manifest
    final manifest = <String, ({String path, String type, String props})>{};
    for (final e in opf.descendantElements) {
      if (e.name.local != 'item') continue;
      final id = e.getAttribute('id');
      final href = e.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (path: _join(opfDir, href), type: e.getAttribute('media-type') ?? '', props: e.getAttribute('properties') ?? '');
    }

    // cover
    var coverPath = '';
    for (final e in opf.descendantElements) {
      if (e.name.local == 'meta' && e.getAttribute('name') == 'cover') {
        final id = e.getAttribute('content');
        if (id != null && manifest[id] != null) coverPath = manifest[id]!.path;
      }
    }
    if (coverPath.isEmpty) {
      for (final m in manifest.values) {
        if (m.props.split(' ').contains('cover-image')) coverPath = m.path;
      }
    }
    if (coverPath.isEmpty) {
      for (final entry in manifest.entries) {
        if (entry.value.type.startsWith('image/') && (entry.key.toLowerCase().contains('cover') || entry.value.path.toLowerCase().contains('cover'))) {
          coverPath = entry.value.path;
          break;
        }
      }
    }

    // spine
    final spine = <EpubSpineItem>[];
    String? tocId;
    for (final e in opf.descendantElements) {
      if (e.name.local == 'spine') tocId = e.getAttribute('toc');
      if (e.name.local == 'itemref') {
        final idref = e.getAttribute('idref');
        final m = idref == null ? null : manifest[idref];
        if (m == null) continue;
        spine.add(EpubSpineItem(idref!, m.path, m.type, (e.getAttribute('linear') ?? 'yes') != 'no'));
      }
    }

    // table of contents: nav document first, then NCX
    var toc = <EpubTocEntry>[];
    for (final m in manifest.values) {
      if (m.props.split(' ').contains('nav')) {
        final t = _text(archive, m.path);
        if (t != null) toc = _parseNav(t, _dir(m.path));
        break;
      }
    }
    if (toc.isEmpty) {
      String? ncxPath = tocId == null ? null : manifest[tocId]?.path;
      ncxPath ??= manifest.values.where((m) => m.type == 'application/x-dtbncx+xml').map((m) => m.path).firstOrNull;
      if (ncxPath != null) {
        final t = _text(archive, ncxPath);
        if (t != null) toc = _parseNcx(t, _dir(ncxPath));
      }
    }

    return EpubPackage(
      opfPath: opfPath,
      title: first('title'),
      author: creators.join(', '),
      language: first('language'),
      description: _plain(first('description')),
      publisher: first('publisher'),
      coverPath: coverPath,
      spine: spine,
      toc: toc,
    );
  }

  static String _plain(String s) => s.isEmpty ? s : (html_parser.parseFragment(s).text ?? s).replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<EpubTocEntry> _parseNav(String htmlText, String dir) {
    final doc = html_parser.parse(htmlText);
    dom.Element? nav;
    for (final n in doc.querySelectorAll('nav')) {
      final type = (n.attributes['epub:type'] ?? n.attributes['type'] ?? '').toLowerCase();
      if (type.contains('toc')) {
        nav = n;
        break;
      }
      nav ??= n;
    }
    if (nav == null) return [];
    final out = <EpubTocEntry>[];
    void walkList(dom.Element ol, int depth) {
      for (final li in ol.children.where((c) => c.localName == 'li')) {
        dom.Element? a;
        dom.Element? sub;
        for (final c in li.children) {
          if (c.localName == 'a' && a == null) a = c;
          if (c.localName == 'span' && a == null) a = c;
          if (c.localName == 'ol' || c.localName == 'ul') sub = c;
        }
        final hasChildren = sub != null && sub.children.any((c) => c.localName == 'li');
        final href = a?.attributes['href'] ?? '';
        if (a != null && href.isNotEmpty) {
          final title = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          final hash = href.indexOf('#');
          final path = hash < 0 ? href : href.substring(0, hash);
          out.add(EpubTocEntry(title, path.isEmpty ? '' : _join(dir, path), hash < 0 ? '' : _decode(href.substring(hash + 1)), depth, hasChildren));
        }
        if (sub != null) walkList(sub, depth + 1);
      }
    }

    final root = nav.children.where((c) => c.localName == 'ol' || c.localName == 'ul').firstOrNull;
    if (root != null) walkList(root, 0);
    return out;
  }

  static List<EpubTocEntry> _parseNcx(String xml, String dir) {
    final doc = XmlDocument.parse(xml);
    final out = <EpubTocEntry>[];
    void walk(XmlElement parent, int depth) {
      for (final np in parent.childElements.where((e) => e.name.local == 'navPoint')) {
        String title = '';
        String src = '';
        for (final c in np.childElements) {
          if (c.name.local == 'navLabel') title = c.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (c.name.local == 'content') src = c.getAttribute('src') ?? '';
        }
        final hasChildren = np.childElements.any((e) => e.name.local == 'navPoint');
        if (src.isNotEmpty) {
          final hash = src.indexOf('#');
          final path = hash < 0 ? src : src.substring(0, hash);
          out.add(EpubTocEntry(title, _join(dir, path), hash < 0 ? '' : _decode(src.substring(hash + 1)), depth, hasChildren));
        }
        walk(np, depth + 1);
      }
    }

    for (final nm in doc.descendantElements.where((e) => e.name.local == 'navMap')) {
      walk(nm, 0);
    }
    return out;
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  // ---------------------------------------------------------------- chapters

  /// TOC + spine -> chapters (see the file comment for the encoding).
  static List<BookChapter> buildChapters(EpubPackage pkg, {String bookUrl = '', String? Function(String path)? titleOfUnlisted}) {
    final byPath = <String, List<EpubTocEntry>>{};
    for (final e in pkg.toc) {
      byPath.putIfAbsent(e.path, () => []).add(e);
    }
    final out = <BookChapter>[];
    void add(String name, String path, String tag, String endAnchor, int spineIndex, bool isVolume) {
      out.add(BookChapter(
        name: name,
        chapterId: path,
        tag: tag,
        baseUrl: endAnchor,
        isVolume: isVolume,
        index: out.length,
        start: spineIndex,
        end: spineIndex,
      ));
    }

    for (var si = 0; si < pkg.spine.length; si++) {
      final item = pkg.spine[si];
      if (!_isDocument(item)) continue;
      final entries = byPath[item.path] ?? const <EpubTocEntry>[];
      if (entries.isEmpty) {
        final t = titleOfUnlisted?.call(item.path) ?? '';
        add(t.isEmpty ? p.basenameWithoutExtension(item.path) : t, item.path, '', '', si, false);
        continue;
      }
      final withFragments = entries.where((e) => e.fragment.isNotEmpty).length;
      if (entries.length == 1 || withFragments == 0) {
        final e = entries.first;
        add(e.title.isEmpty ? p.basenameWithoutExtension(item.path) : e.title, item.path, '', '', si, e.hasChildren && TextFile.isVolumeTitle(e.title));
        continue;
      }
      for (var k = 0; k < entries.length; k++) {
        final e = entries[k];
        final startAnchor = k == 0 ? '' : e.fragment;
        final endAnchor = k + 1 < entries.length ? entries[k + 1].fragment : '';
        add(e.title.isEmpty ? p.basenameWithoutExtension(item.path) : e.title, item.path, startAnchor, endAnchor, si, e.hasChildren && TextFile.isVolumeTitle(e.title));
      }
    }
    return out;
  }

  static bool _isDocument(EpubSpineItem i) {
    final t = i.mediaType.toLowerCase();
    return t.isEmpty || t.contains('html') || t.contains('xml') && !t.contains('ncx');
  }

  // ---------------------------------------------------------------- public API

  /// Parses the book (isolate). [coverDir] receives the extracted cover (`<md5(bookUrl)>.<ext>`).
  static Future<EpubParseResult> parse(File file, {String? bookUrl, Directory? coverDir}) async {
    final path = file.path;
    final url = bookUrl ?? path;
    final coverPath = coverDir?.path;
    final map = await ReadIsolate.run(() => _parseSync(path, url, coverPath));
    return EpubParseResult(
      name: map['name'] as String,
      author: map['author'] as String,
      intro: map['intro'] as String,
      language: map['language'] as String,
      coverFile: map['cover'] as String,
      chapters: (map['chapters'] as List).map((e) => BookChapter.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  static Map<String, dynamic> _parseSync(String path, String bookUrl, String? coverDir) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final pkg = readPackage(archive);
      final chapters = buildChapters(pkg, bookUrl: bookUrl, titleOfUnlisted: (docPath) {
        final t = _text(archive, docPath);
        return t == null ? null : (EpubHtml.guessTitle(t) ?? '');
      });
      var cover = '';
      if (coverDir != null && pkg.coverPath.isNotEmpty) {
        final data = _bytes(archive, pkg.coverPath);
        if (data != null && data.isNotEmpty) {
          final ext = p.extension(pkg.coverPath).isEmpty ? '.jpg' : p.extension(pkg.coverPath);
          final f = File('$coverDir/${ReadFileStore.md5Hex(bookUrl)}$ext');
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(data);
          cover = f.path;
        }
      }
      return {
        'name': pkg.title.isEmpty ? p.basenameWithoutExtension(path) : pkg.title,
        'author': pkg.author,
        'intro': pkg.description,
        'language': pkg.language,
        'cover': cover,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };
    } finally {
      input.closeSync();
    }
  }

  /// Chapter body as blocks. Images are extracted to [imageDir] on demand (`<imageDir>/<archive path>`); without [imageDir]
  /// they are dropped. The chapter title heading at the top of the document is removed (the reader draws its own title).
  static Future<ChapterContent> getChapterContent(File file, BookChapter chapter, {Directory? imageDir}) {
    final path = file.path;
    final docPath = chapter.chapterId;
    final from = chapter.tag;
    final to = chapter.baseUrl;
    final title = chapter.name;
    final dir = imageDir?.path;
    return ReadIsolate.run(() => getChapterContentSync(path, docPath, from, to, title, dir));
  }

  static ChapterContent getChapterContentSync(String zipFile, String docPath, String from, String to, String title, String? imageDir) {
    final input = InputFileStream(zipFile);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final text = _text(archive, docPath);
      if (text == null) return ChapterContent.empty;
      String? resolve(String archivePath) {
        if (archivePath.startsWith('data:')) return archivePath;
        if (imageDir == null) return null;
        final out = File('$imageDir/$archivePath');
        if (!out.existsSync()) {
          final data = _bytes(archive, archivePath);
          if (data == null) return null;
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(data);
        }
        return out.path;
      }

      final dir = _dir(docPath);
      var content = EpubHtml.toContent(text, archiveDir: dir, resolveImage: resolve, fromAnchor: from, toAnchor: to);
      if (content.isEmpty && (from.isNotEmpty || to.isNotEmpty)) {
        content = EpubHtml.toContent(text, archiveDir: dir, resolveImage: resolve);
      }
      return dropLeadingTitle(content, title);
    } finally {
      input.closeSync();
    }
  }

  /// Removes the first block when it is just the chapter title (offsets of the rest are shifted).
  static ChapterContent dropLeadingTitle(ChapterContent c, String title) {
    if (c.blocks.isEmpty || c.blocks.first.isImage) return c;
    String norm(String s) => s.replaceAll(RegExp(r'[\s　]+'), '');
    final first = c.blocks.first;
    final firstText = first.runs.map((r) => r.str).join();
    if (firstText.isEmpty || norm(firstText) != norm(title)) return c;
    final shift = c.blocks.length > 1 ? firstText.length + 1 : firstText.length;
    final rest = c.blocks.skip(1).map((b) {
      for (final r in b.runs) {
        if (r.start >= 0) r.start -= shift;
        if (r.end >= 0) r.end -= shift;
      }
      return b;
    }).toList();
    return ChapterContent(c.text.length >= shift ? c.text.substring(shift) : '', rest);
  }
}
