// read/local_book_importer.dart — turns a local file (txt / epub / mobi / azw) into a [Book] with its chapter list and gives the reader
// lazy access to the chapter text.
//
// Convention of the original (0xd97fa4 / 0xd97f1c / 0xd97e90): a local book has `Book.origin == "loc_book"` and its `bookUrl` ends in
// `.txt` / `.epub` / `.mobi`. The imported file is copied into `<ReadStorageRoot>/books/` and `bookUrl` is the path relative to the
// storage root (`books/<file name>`), so it stays valid when the app container moves (iOS changes the absolute path after updates);
// with `copy: false` the absolute path of the original file is used. The parsed chapter list is cached as
// `<root>/books/<md5(bookUrl)>.chapters.json` so re-opening a book does not parse a 20 MB file again.
//
// Shelf UI usage:
//   final importer = LocalBookImporter();
//   final local = await importer.import(file);            // LocalBook { book, chapters, ... }
//   // persist local.book in the shelf; later:
//   final chapters = await importer.loadChapters(book);   // cached list or re-parse
//   final api = ReadApi(book, chapters: chapters, loader: importer.loaderFor(book));
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/bookchapter.dart';
import '../models/txt_toc_rule.dart';
import 'api/read_file_store.dart';
import 'api/read_storage_root.dart';
import 'api/readapi.dart';
import 'epub/epub_file.dart';
import 'mobi/mobi_file.dart';
import 'txt/text_file.dart';
import 'util/chapter_content.dart';

class LocalBook {
  final Book book;
  final List<BookChapter> chapters;
  final File file;

  /// `txt`, `epub` or `mobi`.
  final String format;

  const LocalBook(this.book, this.chapters, this.file, this.format);
}

class LocalBookException implements Exception {
  final String message;
  const LocalBookException(this.message);
  @override
  String toString() => message;
}

class LocalBookImporter {
  static const List<String> supportedExtensions = ['txt', 'epub', 'mobi', 'azw', 'azw3', 'prc'];

  /// Where imported files / covers / extracted EPUB images go (defaults below [ReadStorageRoot]).
  final Directory? booksDirOverride;
  final Directory? coversDirOverride;
  final Directory? epubDirOverride;
  final Directory? mobiDirOverride;

  const LocalBookImporter({this.booksDirOverride, this.coversDirOverride, this.epubDirOverride, this.mobiDirOverride});

  Directory get booksDir => booksDirOverride ?? ReadStorageRoot.sub('books');
  Directory get coversDir => coversDirOverride ?? ReadStorageRoot.sub(ReadStorageRoot.covers);
  Directory get epubDir => epubDirOverride ?? ReadStorageRoot.sub(ReadStorageRoot.epub);
  Directory get mobiDir => mobiDirOverride ?? ReadStorageRoot.sub('mobi');

  static String formatOf(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext == 'txt') return 'txt';
    if (ext == 'epub') return 'epub';
    if (const ['mobi', 'azw', 'azw3', 'prc'].contains(ext)) return 'mobi';
    throw LocalBookException('不支持的文件格式: .$ext');
  }

  static bool isSupported(String path) => supportedExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

  // ---------------------------------------------------------------- import

  /// Imports [file]. [txtRules] are the user's TXT TOC rules (`data/txtrule`); null uses the built-in defaults.
  Future<LocalBook> import(File file, {List<TxtTocRule>? txtRules, String? charset, bool copy = true}) async {
    if (!file.existsSync()) throw LocalBookException('文件不存在: ${file.path}');
    final format = formatOf(file.path);
    final target = copy ? _copyIntoLibrary(file) : file;
    final bookUrl = copy ? _relativeUrl(target) : target.path;
    final now = DateTime.now().millisecondsSinceEpoch;

    late List<BookChapter> chapters;
    late Book book;
    switch (format) {
      case 'txt':
        final res = await TextFile.parse(target, rules: txtRules, charset: charset, bookUrl: bookUrl);
        if (res.chapters.isEmpty) throw const LocalBookException('文件内容为空');
        chapters = res.chapters;
        book = Book(
          name: res.name,
          author: res.author,
          charset: res.charset,
          kind: 'TXT',
          wordCount: _wordCount(res.byteLength, res.charset),
        );
      case 'epub':
        final res = await EpubFile.parse(target, bookUrl: bookUrl, coverDir: coversDir);
        if (res.chapters.isEmpty) throw const LocalBookException('EPUB 中没有可阅读的章节');
        chapters = res.chapters;
        book = Book(
          name: res.name,
          author: res.author,
          intro: res.intro,
          coverUrl: res.coverFile,
          charset: 'UTF-8',
          kind: 'EPUB',
        );
      default:
        final res = await MobiFile.parse(target, workDir: _mobiWork(bookUrl), coverDir: coversDir, bookUrl: bookUrl);
        if (res.chapters.isEmpty) throw const LocalBookException('MOBI 中没有可阅读的章节');
        chapters = res.chapters;
        book = Book(
          name: res.name,
          author: res.author,
          intro: res.intro,
          coverUrl: res.coverFile,
          charset: res.charset,
          kind: 'MOBI',
        );
    }

    book
      ..bookUrl = bookUrl
      ..tocUrl = bookUrl
      ..origin = ReadApi.localOrigin
      ..totalChapterNum = chapters.length
      ..latestChapterTitle = chapters.last.name
      ..latestChapterTime = now
      ..lastCheckTime = now
      ..durChapterTitle = chapters.first.name
      ..durChapterIndex = 0
      ..durChapterPos = 0
      ..durChapterTime = now;
    await saveChapters(book, chapters);
    return LocalBook(book, chapters, target, format);
  }

  File _copyIntoLibrary(File src) {
    final dir = booksDir..createSync(recursive: true);
    // Already inside the library: keep it.
    if (p.isWithin(dir.path, src.path)) return src;
    final base = p.basenameWithoutExtension(src.path);
    final ext = p.extension(src.path);
    var dest = File('${dir.path}/$base$ext');
    var n = 1;
    while (dest.existsSync()) {
      if (dest.lengthSync() == src.lengthSync()) return dest; // the same file imported twice
      dest = File('${dir.path}/${base}_$n$ext');
      n++;
    }
    return src.copySync(dest.path);
  }

  String _relativeUrl(File f) {
    final root = ReadStorageRoot.isSet ? ReadStorageRoot.dir.path : null;
    if (root != null && p.isWithin(root, f.path)) return p.relative(f.path, from: root).replaceAll('\\', '/');
    return f.path;
  }

  Directory _mobiWork(String bookUrl) => Directory('${mobiDir.path}/${ReadFileStore.md5Hex(bookUrl)}');

  static String _wordCount(int bytes, String charset) {
    final chars = charset == 'UTF-8' ? bytes / 3 : bytes / 2;
    return chars >= 10000 ? '${(chars / 10000).toStringAsFixed(1)}万字' : '${chars.round()}字';
  }

  // ---------------------------------------------------------------- files and chapters

  /// The file of a local book: absolute `bookUrl` as is, else relative to the storage root.
  static File fileOf(Book book) {
    final u = book.bookUrl;
    if (p.isAbsolute(u)) return File(u);
    return File('${ReadStorageRoot.dir.path}/$u');
  }

  File _chaptersFile(Book book) => File('${booksDir.path}/${ReadFileStore.md5Hex(book.bookUrl)}.chapters.json');

  Future<void> saveChapters(Book book, List<BookChapter> chapters) async {
    final f = _chaptersFile(book);
    final json = jsonEncode(chapters.map((c) => c.toJson()).toList());
    await ReadIsolate.run(() => ReadFileStore.writeTextSync(f, json));
  }

  /// Chapter list of an imported book: the cached list, else a fresh parse of the file (which refreshes the cache).
  Future<List<BookChapter>> loadChapters(Book book, {List<TxtTocRule>? txtRules, bool reparse = false}) async {
    if (!reparse) {
      final cached = ReadFileStore.decodeList(ReadFileStore.readTextSync(_chaptersFile(book)));
      if (cached != null && cached.isNotEmpty) {
        return [for (final e in cached) BookChapter.fromJson(Map<String, dynamic>.from(e as Map))];
      }
    }
    final file = fileOf(book);
    if (!file.existsSync()) throw LocalBookException('找不到本地书籍文件: ${book.bookUrl}');
    final List<BookChapter> chapters;
    switch (formatOf(file.path)) {
      case 'txt':
        chapters = (await TextFile.parse(file, rules: txtRules, charset: book.charset, bookUrl: book.bookUrl)).chapters;
      case 'epub':
        chapters = (await EpubFile.parse(file, bookUrl: book.bookUrl)).chapters;
      default:
        chapters = (await MobiFile.parse(file, workDir: _mobiWork(book.bookUrl), bookUrl: book.bookUrl)).chapters;
    }
    await saveChapters(book, chapters);
    return chapters;
  }

  /// Body of one chapter as blocks for the layout engine.
  Future<ChapterContent> loadChapterContent(Book book, BookChapter chapter) async {
    final file = fileOf(book);
    if (!file.existsSync()) throw LocalBookException('找不到本地书籍文件: ${book.bookUrl}');
    switch (formatOf(file.path)) {
      case 'txt':
        return ChapterContent.fromText(await TextFile.readChapter(file, chapter, book.charset));
      case 'epub':
        final imgDir = Directory('${epubDir.path}/${ReadFileStore.md5Hex(book.bookUrl)}');
        return EpubFile.getChapterContent(file, chapter, imageDir: imgDir);
      default:
        return MobiFile.getChapterContent(chapter, book.charset);
    }
  }

  /// A [ChapterLoader] for `ReadApi`.
  Future<ChapterContent> Function(BookChapter chapter) loaderFor(Book book) => (chapter) => loadChapterContent(book, chapter);

  /// Removes everything the importer stored for [book] (copied file, chapter cache, extracted images, cover).
  Future<void> delete(Book book) async {
    final file = fileOf(book);
    final inLibrary = p.isWithin(booksDir.path, file.path);
    if (inLibrary) ReadFileStore.deleteSync(file);
    ReadFileStore.deleteSync(_chaptersFile(book));
    final key = ReadFileStore.md5Hex(book.bookUrl);
    for (final d in [Directory('${epubDir.path}/$key'), _mobiWork(book.bookUrl)]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    if (book.coverUrl.isNotEmpty && p.isWithin(coversDir.path, book.coverUrl)) ReadFileStore.deleteSync(File(book.coverUrl));
  }
}
