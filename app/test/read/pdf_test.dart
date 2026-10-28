// PDF books: imported with one chapter 全文, every page an image `pdf:<file>,<page>`, pages rendered on demand into the cache.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/local_book_importer.dart';
import 'package:newread/read/pdf/pdf_file.dart';

class _FakeRenderer implements PdfRenderer {
  final List<int> rendered = [];
  @override
  Future<int> pageCount(String path) async => 3;
  @override
  Future<Size> pageSize(String path, int index) async => const Size(595, 842);
  @override
  Future<Uint8List> render(String path, int index, {double width = 1080}) async {
    rendered.add(index);
    return Uint8List.fromList([137, 80, 78, 71, index]);
  }
}

void main() {
  late Directory tmp;
  late _FakeRenderer r;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_pdf_');
    ReadStorageRoot.dir = tmp;
    r = _FakeRenderer();
    PdfRenderer.instance = r;
  });
  tearDown(() {
    PdfRenderer.instance = PdfxRenderer();
    tmp.deleteSync(recursive: true);
  });

  test('import, chapter content, page cache', () async {
    expect(LocalBookImporter.isSupported('a.PDF'), isTrue);
    final local = await const LocalBookImporter().import(File('test/fixtures/reader_ui/sample.pdf'));
    expect(local.book.name, 'sample');
    expect(local.book.kind, 'PDF');
    expect(local.chapters.single.name, '全文');
    expect(local.chapters.single.chapterId, PdfFile.allPages);
    final content = await const LocalBookImporter().loadChapterContent(local.book, local.chapters.single);
    final srcs = [for (final b in content.blocks) b.runs.first.href];
    final path = LocalBookImporter.fileOf(local.book).path;
    expect(srcs, [for (var i = 0; i < 3; i++) 'pdf:$path,$i']);
    expect(PdfFile.parseSrc(srcs[1]), (path, 1));
    expect(await PdfFile.sizeOf(srcs[0]), const Size(595, 842));
    final f = await PdfFile.pageFile(path, 2);
    expect(f.readAsBytesSync().last, 2);
    await PdfFile.pageFile(path, 2);
    expect(r.rendered, [2], reason: 'the second request reads the cache');
    expect(await const LocalBookImporter().loadChapters(local.book, reparse: true), hasLength(1));
    await const LocalBookImporter().delete(local.book);
    expect(f.existsSync(), isFalse);
  });

  test('a renderer failure is the original message', () async {
    PdfRenderer.instance = _Broken();
    expect(() => PdfFile.chapterContent('/x.pdf'), throwsA(predicate((e) => '$e'.contains('获取PDF章节内容失败: '))));
  });
}

class _Broken extends _FakeRenderer {
  @override
  Future<int> pageCount(String path) async => throw StateError('bad file');
}
