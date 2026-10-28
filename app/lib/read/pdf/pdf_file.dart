// read/pdf/pdf_file.dart — PDF books as the original reads them: the table of contents is one chapter "全文" (url `all_pages`, here the
// chapterId; 0xedad38), its content is every page as an image `<img src="pdf:<file>,<page>"  />` (0xf136d4: "渲染第 n 页失败: ",
// "没有成功渲染任何页面", "获取PDF章节内容失败: "), and the image loader renders a `pdf:` source on demand (0xeb5758 / 0xed0f2c).
// Rendering goes through [PdfRenderer] (pdfx on a device; tests use a fake). Rendered pages are cached as PNG files under
// `<root>/pdf/<md5(file)>/<page>.png`, so the layout engine and the page view read them like any local image.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:pdfx/pdfx.dart';

import '../../models/bookchapter.dart';
import '../api/read_file_store.dart';
import '../api/read_storage_root.dart';
import '../util/chapter_content.dart';
import '../model/line.dart';
import '../model/page.dart';

abstract class PdfRenderer {
  static PdfRenderer instance = PdfxRenderer();

  Future<int> pageCount(String path);

  /// Size of page [index] (0-based) in PDF points.
  Future<Size> pageSize(String path, int index);

  /// PNG of page [index] rendered [width] pixels wide.
  Future<Uint8List> render(String path, int index, {double width = 1080});
}

class PdfxRenderer implements PdfRenderer {
  final Map<String, Future<PdfDocument>> _docs = {};

  Future<PdfDocument> _open(String path) => _docs.putIfAbsent(path, () => PdfDocument.openFile(path));

  @override
  Future<int> pageCount(String path) async => (await _open(path)).pagesCount;

  @override
  Future<Size> pageSize(String path, int index) async {
    final page = await (await _open(path)).getPage(index + 1);
    try {
      return Size(page.width, page.height);
    } finally {
      await page.close();
    }
  }

  @override
  Future<Uint8List> render(String path, int index, {double width = 1080}) async {
    final page = await (await _open(path)).getPage(index + 1);
    try {
      final h = width * page.height / page.width;
      final img = await page.render(width: width, height: h, format: PdfPageImageFormat.png, backgroundColor: '#FFFFFF');
      if (img == null) throw StateError('渲染第 ${index + 1} 页失败');
      return img.bytes;
    } finally {
      await page.close();
    }
  }
}

abstract class PdfFile {
  static const String allPages = 'all_pages';
  static const String scheme = 'pdf:';

  /// The table of contents: one chapter with every page.
  static List<BookChapter> chapters() => [BookChapter(name: '全文', chapterId: allPages, index: 0)];

  static String pageSrc(String path, int index) => '$scheme$path,$index';

  /// `pdf:<path>,<index>` -> (path, index); null for other sources.
  static (String, int)? parseSrc(String src) {
    if (!src.startsWith(scheme)) return null;
    final body = src.substring(scheme.length);
    final comma = body.lastIndexOf(',');
    if (comma < 0) return null;
    final i = int.tryParse(body.substring(comma + 1));
    if (i == null) return null;
    return (body.substring(0, comma), i);
  }

  /// The chapter: one image block per page.
  static Future<ChapterContent> chapterContent(String path) async {
    try {
      final n = await PdfRenderer.instance.pageCount(path);
      if (n <= 0) throw StateError('没有成功渲染任何页面');
      return ChapterContent.fromBlocks([
        for (var i = 0; i < n; i++) CalcuPages.image(CLine(type: CLineType.image, style: CLineStyle.image, href: pageSrc(path, i))),
      ]);
    } catch (e) {
      throw StateError('获取PDF章节内容失败: $e');
    }
  }

  static Directory _cacheDir(String path) => Directory('${ReadStorageRoot.sub('pdf').path}/${ReadFileStore.md5Hex(path)}');

  /// The rendered page as a cached PNG file (rendered on first use).
  static Future<File> pageFile(String path, int index) async {
    final dir = _cacheDir(path);
    final f = File('${dir.path}/$index.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await PdfRenderer.instance.render(path, index);
    dir.createSync(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Image size for the layout engine.
  static Future<Size?> sizeOf(String src) async {
    final s = parseSrc(src);
    if (s == null) return null;
    try {
      return await PdfRenderer.instance.pageSize(s.$1, s.$2);
    } catch (_) {
      return null;
    }
  }

  /// Removes the rendered pages of a book.
  static void deleteCache(String path) {
    final d = _cacheDir(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
