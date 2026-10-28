// Per-book storage (BookContent / BookRules / BookHight / BookAi / BookMark), ReadApi (chapter loading, purification, progress, history).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/models/replacerule.dart';
import 'package:newread/read/api/book_ai.dart';
import 'package:newread/read/api/book_audio.dart';
import 'package:newread/read/api/book_content.dart';
import 'package:newread/read/api/book_hight.dart';
import 'package:newread/read/api/book_mark.dart';
import 'package:newread/read/api/book_rules.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_progress_remote.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/util/cache_book.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/replace_rules.dart';

class _FakeRemote implements ReadProgressRemote {
  final List<String> calls = [];
  bool fail = false;

  @override
  Future<void> autoPos(Book book, int index, double pos) async {
    calls.add('autopos ${book.bookUrl} $index $pos');
    if (fail) throw StateError('offline');
  }

  @override
  Future<void> addReads(Book book) async {
    calls.add('addreads ${book.bookUrl} ${book.readchapter}');
  }
}

Book _webBook({bool rules = false}) => Book(bookUrl: 'https://example.com/book/1', name: '测试书', author: 'A', origin: 'https://example.com', useReplaceRule: rules);

List<BookChapter> _chapters(int n) => [for (var i = 0; i < n; i++) BookChapter(name: '第${i + 1}章', index: i, chapterId: 'c$i')];

ReplaceRule _rule(String pattern, String replacement, {bool regex = false, bool title = false, bool content = true, String scope = '', String exclude = '', int order = 0, String id = ''}) =>
    ReplaceRule(
      id: id,
      name: pattern,
      pattern: pattern,
      replacement: replacement,
      isRegex: regex,
      scopeTitle: title,
      scopeContent: content,
      scope: scope,
      excludeScope: exclude,
      isEnabled: true,
      ruleorder: order,
    );

void main() {
  late Directory tmp;

  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_api_');
    ReadStorageRoot.dir = tmp;
    ReadApi.resetCaches();
    ReadApi.onProgress = null;
    ReadApi.remote = null;
    ReadApi.log = null;
    ReplaceRuleEngine.disabled.clear();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('file store', () {
    test('md5 naming and atomic write', () {
      expect(ReadFileStore.md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
      final f = ReadFileStore.fileFor(tmp, 'key');
      ReadFileStore.writeTextSync(f, 'v1');
      ReadFileStore.writeTextSync(f, 'v2');
      expect(f.path, endsWith('${ReadFileStore.md5Hex('key')}.txt'));
      expect(ReadFileStore.readTextSync(f), 'v2');
      expect(File('${f.path}.tmp').existsSync(), isFalse);
      expect(ReadFileStore.readTextSync(File('${tmp.path}/none.txt')), isNull);
    });

    test('real isolates work for the stores', () async {
      ReadIsolate.enabled = true;
      addTearDown(() => ReadIsolate.enabled = false);
      const store = BookContent();
      await store.saveToLocal('u', 3, '正文三');
      expect(await store.readFromLocal('u', 3), '正文三');
      expect(await store.readFromLocal('u', 4), isNull);
    });
  });

  group('BookContent', () {
    test('layout on disk, round trip, delete', () async {
      const store = BookContent();
      final book = _webBook();
      await store.saveToLocal(book.bookUrl, 0, '第一章正文', book: book);
      await store.saveToLocal(book.bookUrl, 2, '第三章正文', book: book);
      final dir = Directory('${tmp.path}/bookcache2/${ReadFileStore.md5Hex(book.bookUrl)}');
      expect(dir.existsSync(), isTrue);
      expect(File('${dir.path}/book.json').existsSync(), isTrue);
      expect(Book.fromJson(jsonDecode(File('${dir.path}/book.json').readAsStringSync()) as Map<String, dynamic>).name, '测试书');
      expect(File('${dir.path}/${ReadFileStore.md5Hex('0')}.txt').readAsStringSync(), '第一章正文');
      expect(await store.readFromLocal(book.bookUrl, 2), '第三章正文');
      expect(store.cachedIndexesSync(book.bookUrl, 4), {0, 2});
      await store.deleteChapter(book.bookUrl, 0);
      expect(store.cachedIndexesSync(book.bookUrl, 4), {2});
      await store.deleteBook(book.bookUrl);
      expect(dir.existsSync(), isFalse);
    });
  });

  group('rule / highlight / ai contexts', () {
    test('BookRules', () async {
      final store = BookRules();
      expect(await store.readFromLocal('u', 1), isNull);
      await store.saveToLocal('u', 1, RuleContext(md5: 'abc', text: '净化后', rules: [_rule('a', 'b')]));
      final r = (await store.readFromLocal('u', 1))!;
      expect(r.md5, 'abc');
      expect(r.text, '净化后');
      expect(r.rules.single.pattern, 'a');
      await store.deleteBook('u');
      expect(await store.readFromLocal('u', 1), isNull);
    });

    test('BookHight and BookAi', () async {
      final h = BookHight();
      await h.saveToLocal('u', 0, HContext(oldtext: 'o', text: '<span>t</span>', md5: 'm'));
      expect((await h.readFromLocal('u', 0))!.text, '<span>t</span>');
      final a = BookAi();
      await a.saveToLocal('u', 0, AiContext(oldtext: 'o', text: 'n'));
      expect((await a.readFromLocal('u', 0))!.oldtext, 'o');
      expect(Directory('${tmp.path}/high').existsSync(), isTrue);
      expect(Directory('${tmp.path}/bookai').existsSync(), isTrue);
    });

    test('BookAudio folder naming', () {
      const audio = BookAudio();
      expect(audio.dirFor('u').path, endsWith('audio2/${ReadFileStore.md5Hex('u')}'));
      expect(audio.fileFor('u', 5).path, endsWith('/5.mp3'));
    });
  });

  group('BookMark', () {
    test('add, list, replace at the same position, remove, version notifier', () async {
      const marks = BookMark();
      var notified = 0;
      void listener() => notified++;
      BookMark.bookmarkVersion.addListener(listener);
      addTearDown(() => BookMark.bookmarkVersion.removeListener(listener));

      expect(await marks.getMarks('u'), isEmpty);
      final a = await marks.add('u', chapterIndex: 2, chapterName: '第三章', position: 0.5);
      await marks.add('u', chapterIndex: 2, chapterName: '第三章', position: 0.5);
      await marks.add('u', chapterIndex: 5, chapterName: '第六章', position: 0.1);
      var list = await marks.getMarks('u');
      expect(list.length, 2);
      expect(list.map((m) => m.cname), containsAll(['第三章', '第六章']));
      await marks.remove('u', list.firstWhere((m) => m.cindex == 5).id);
      list = await marks.getMarks('u');
      expect(list.single.cindex, 2);
      expect(a.cpos, 0.5);
      expect(notified, greaterThanOrEqualTo(4));
    });
  });

  group('replace rules', () {
    test('scope and exclude scope, title vs content, order', () {
      final book = _webBook(rules: true);
      final rules = [
        _rule('a', 'x', order: 2),
        _rule('b', 'y', scope: 'https://example.com,其他', order: 1),
        _rule('c', 'z', scope: 'other.org'),
        _rule('d', 'w', exclude: '测试书'),
        _rule('e', 'v', title: true, content: false),
      ];
      final content = ReplaceRuleEngine.select(rules, book, title: false);
      expect(content.map((r) => r.pattern).toList(), ['b', 'a']);
      final title = ReplaceRuleEngine.select(rules, book, title: true);
      expect(title.map((r) => r.pattern).toList(), ['e']);
    });

    test('regex with group references, plain text, bad pattern skipped', () {
      final out = ReplaceRuleEngine.apply('第12章 AB 广告', [
        _rule(r'第(\d+)章', r'Chapter $1', regex: true),
        _rule('广告', ''),
        _rule('(oops', 'x', regex: true),
        _rule(r'(A)(B)', r'${2}\$$1', regex: true),
      ]);
      expect(out, r'Chapter 12 B$A ');
    });

    test('HTML entities', () {
      expect(ReadApi.decodeHtmlEntities('a&nbsp;b &lt;i&gt; &quot;q&quot; &amp;amp; &#8212; &#x4e2d; &hellip;'), 'a b <i> "q" &amp; — 中 …');
      expect(ReadApi.decodeHtmlEntities('plain'), 'plain');
    });
  });

  group('ReadApi chapter loading', () {
    test('loads through the loader once, then from the cache; refresh bypasses it', () async {
      var loads = 0;
      final api = ReadApi(_webBook(), chapters: _chapters(3), loader: (c) async {
        loads++;
        return ChapterContent.fromText('${c.name}的正文\n第二段');
      });
      final a = await api.loadChapter(1);
      expect(a.content.text, '第2章的正文\n第二段');
      expect(a.title, '第2章');
      expect(a.purified, isFalse);
      await api.loadChapter(1);
      expect(loads, 1);
      await api.loadChapter(1, refresh: true);
      expect(loads, 2);
      expect(() => api.loadChapter(9), throwsRangeError);
    });

    test('purification result is cached per chapter and invalidated by a rule change', () async {
      var loads = 0;
      final book = _webBook(rules: true);
      final api = ReadApi(book, chapters: _chapters(2), loader: (c) async {
        loads++;
        return ChapterContent.fromText('广告开头\n正文内容广告');
      }, replaceRules: [_rule('广告', '', id: 'r1'), _rule(r'^第(\d)章$', r'Ch$1', regex: true, title: true, content: false)]);
      final a = await api.loadChapter(0);
      expect(a.content.text, '开头\n正文内容');
      expect(a.purified, isTrue);
      expect(a.title, 'Ch1');
      expect((await api.bookRules.readFromLocal(book.bookUrl, 0))!.text, '开头\n正文内容');

      // same rules: the stored result is used (tamper with it to prove it)
      final ctx = (await api.bookRules.readFromLocal(book.bookUrl, 0))!;
      ctx.text = '来自缓存';
      await api.bookRules.saveToLocal(book.bookUrl, 0, ctx);
      expect((await api.loadChapter(0)).content.text, '来自缓存');

      // different rules: recomputed
      api.replaceRules = [_rule('开头', 'START', id: 'r2')];
      expect((await api.loadChapter(0)).content.text, '广告START\n正文内容广告');
      expect(loads, 1, reason: 'the raw text stays cached');
    });

    test('AI result replaces the text when it was made for the same chapter text', () async {
      final book = _webBook()..useai = true;
      final api = ReadApi(book, chapters: _chapters(1), loader: (c) async => ChapterContent.fromText('原文'));
      await api.bookai.saveToLocal(book.bookUrl, 0, AiContext(oldtext: '原文', text: 'AI净化后'));
      expect((await api.loadChapter(0)).content.text, 'AI净化后');
      await api.bookai.saveToLocal(book.bookUrl, 0, AiContext(oldtext: '别的文本', text: '不应使用'));
      ReadApi.aiPurifier = (t) async => throw Exception('offline');
      final errors = <String>[];
      ReadApi.aiError = errors.add;
      addTearDown(() {
        ReadApi.aiPurifier = (t) async => t;
        ReadApi.aiError = null;
      });
      expect((await api.loadChapter(0)).content.text, '原文'); // the model failed: the chapter is shown unpurified
      expect(errors.single, startsWith('Ai净化出错'));
    });

    test('Ai净化 asks the purify model for chapters without a result, keeps it, and runs at most `concurrent` at a time', () async {
      final book = _webBook()..useai = true;
      var running = 0, peak = 0, calls = 0;
      ReadApi.aiConcurrency = () => 1;
      ReadApi.aiPurifier = (t) async {
        calls++;
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        running--;
        return '净化:$t';
      };
      addTearDown(() => ReadApi.aiConcurrency = () => 1);
      final api = ReadApi(book, chapters: _chapters(3), loader: (c) async => ChapterContent.fromText('原文${c.index}'));
      final r = await Future.wait([api.loadChapter(0), api.loadChapter(1), api.loadChapter(2)]);
      expect(r.map((e) => e.content.text), ['净化:原文0', '净化:原文1', '净化:原文2']);
      expect(peak, 1);
      final stored = await api.bookai.readFromLocal(book.bookUrl, 1);
      expect(stored!.oldtext, '原文1');
      expect(stored.text, '净化:原文1');
      ReadApi.resetCaches();
      expect((await api.loadChapter(1)).content.text, '净化:原文1');
      expect(calls, 3, reason: 'the stored result is reused');
      ReadApi.aiConcurrency = () => 2;
      book.bookUrl = 'https://example.com/book/2';
      peak = 0;
      await Future.wait([api.loadChapter(0), api.loadChapter(1), api.loadChapter(2)]);
      expect(peak, 2);
    });

    test('local books are not cached in bookcache2', () async {
      final book = Book(bookUrl: 'books/a.txt', name: 'a', origin: ReadApi.localOrigin);
      var loads = 0;
      final api = ReadApi(book, chapters: _chapters(1), loader: (c) async {
        loads++;
        return ChapterContent.fromText('x');
      });
      await api.loadChapter(0);
      await api.loadChapter(0);
      expect(loads, 2);
      expect(Directory('${tmp.path}/bookcache2').existsSync(), isFalse);
    });
  });

  group('progress', () {
    test('saveProgress updates the book, history, shelf hook and server', () async {
      final remote = _FakeRemote();
      ReadApi.remote = remote;
      final saved = <Book>[];
      ReadApi.onProgress = (b) async => saved.add(Book.fromJson(b.toJson()));
      final book = _webBook();
      final api = ReadApi(book, chapters: _chapters(10));

      final p = await api.saveProgress(chapterIndex: 3, pos: 0.123456);
      expect(p.pos, 0.1235); // 1/10000 resolution
      expect(book.durChapterIndex, 3);
      expect(book.durChapterTitle, '第4章');
      expect(book.durChapterPos, 0.1235);
      expect(book.readchapter, '3');
      expect(saved.single.durChapterIndex, 3);
      await Future<void>.delayed(Duration.zero);
      expect(remote.calls, ['autopos https://example.com/book/1 3 0.1235', 'addreads https://example.com/book/1 3']);

      await api.saveProgress(chapterIndex: 1, pos: 0.0);
      expect(book.readchapter, '1,3');
      final hist = await ReadApi.getHistory(refresh: true);
      expect(hist.single.durChapterIndex, 1);

      // a server failure never throws into the reader
      remote.fail = true;
      final msgs = <String>[];
      ReadApi.log = msgs.add;
      await api.saveProgress(chapterIndex: 2, pos: 1.5);
      await Future<void>.delayed(Duration.zero);
      expect(book.durChapterPos, 1.0);
      expect(msgs.any((m) => m.contains('阅读进度保存错误')), isTrue);
    });

    test('local books are never uploaded', () async {
      final remote = _FakeRemote();
      ReadApi.remote = remote;
      final book = Book(bookUrl: 'books/a.txt', name: 'a', origin: ReadApi.localOrigin);
      await ReadApi(book, chapters: _chapters(2)).saveProgress(chapterIndex: 1, pos: 0.5);
      await Future<void>.delayed(Duration.zero);
      expect(remote.calls, isEmpty);
    });

    test('history: most recent first, one entry per book, persisted in the item store, capped', () async {
      for (var i = 0; i < 5; i++) {
        await ReadApi.saveRead(Book(bookUrl: 'u$i', name: 'b$i'));
      }
      await ReadApi.saveRead(Book(bookUrl: 'u1', name: 'b1 again'));
      var list = await ReadApi.getHistory();
      expect(list.map((b) => b.bookUrl).toList(), ['u1', 'u4', 'u3', 'u2', 'u0']);
      expect(list.first.name, 'b1 again');
      // file store naming: <root>/item/<md5('historybook')>.txt
      final f = File('${tmp.path}/item/${ReadFileStore.md5Hex('historybook')}.txt');
      expect(f.existsSync(), isTrue);
      ReadApi.resetCaches();
      list = await ReadApi.getHistory();
      expect(list.length, 5);
      await ReadApi.removeFromHistory('u4');
      ReadApi.resetCaches();
      expect((await ReadApi.getHistory()).map((b) => b.bookUrl), isNot(contains('u4')));

      for (var i = 0; i < ReadApi.historyLimit + 20; i++) {
        await ReadApi.saveRead(Book(bookUrl: 'x$i'));
      }
      expect((await ReadApi.getHistory()).length, ReadApi.historyLimit);
    });

    test('read-chapter marks', () async {
      expect(ReadApi.parseRead('3, 1,2,，x,2'), [1, 2, 3]);
      expect(ReadApi.joinRead({5, 1, 3}), '1,3,5');
      final b = Book(bookUrl: 'u', readchapter: '1,2');
      final hist = [Book(bookUrl: 'u', readchapter: '1,2'), Book(bookUrl: 'v', readchapter: '9')];
      expect(await ReadApi.getBookread({'hostorys': hist, 'book': b}), ['1', '2']);
      expect(await ReadApi.postreads({'reads': [3, 1], 'hreads': ['1', '2', 'x']}), {1, 2, 3});
      final out = await ReadApi.savereads({'historys': hist, 'bookUrl': 'u', 'reads': [7], 'hreads': ['1', '2']});
      expect(out.first.readchapter, '1,2,7');
      expect(out.last.readchapter, '9');
    });

    test('directory JSON', () async {
      final list = await ReadApi.parseDirectoryListJson(jsonEncode({
        'directoryList': [
          {'name': '序', 'chapterId': 'a'},
          {'name': '一', 'index': 7},
        ],
      }));
      expect(list.map((c) => c.name), ['序', '一']);
      expect(list.map((c) => c.index), [0, 7]);
      expect((await ReadApi.parseDirectoryListJson('[{"name":"x"}]')).single.name, 'x');
      expect(ReadApi.parseDirectoryListJson('not json'), throwsA(isA<FormatException>()));
    });
  });

  group('server remote', () {
    test('posts autopos / addreads with the documented keys, only when enabled', () async {
      final posts = <(String, Map<String, dynamic>)>[];
      var enabled = false;
      final remote = ServerReadProgressRemote(
        post: (url, body) async {
          posts.add((url, body));
          return {'code': 0};
        },
        enabled: () => enabled,
      );
      final book = Book(bookUrl: 'u', bid: 'B1', readchapter: '1,2');
      await remote.autoPos(book, 2, 0.5);
      expect(posts, isEmpty);
      enabled = true;
      await remote.autoPos(book, 2, 0.5);
      await remote.addReads(book);
      expect(posts[0].$1, endsWith('autopos'));
      expect(posts[0].$2.keys, containsAll(['st', 'tockenid', 'appid', 'book', 'index', 'pos', 'bid', 't']));
      expect(posts[0].$2['book'], 'u');
      expect(posts[1].$1, endsWith('addreads'));
      expect(posts[1].$2['readchapter'], '1,2');
      final bad = ServerReadProgressRemote(post: (u, b) async => {'code': -1, 'errorMsg': 'nope'}, enabled: () => true);
      expect(bad.autoPos(book, 0, 0), throwsA(anything));
    });
  });

  group('CacheBook', () {
    test('caches a range, skips cached / volume / paid chapters, reports progress and failures', () async {
      final chapters = _chapters(8);
      chapters[1].isVolume = true;
      chapters[2].isPay = true;
      final book = _webBook();
      final started = <int>[];
      final api = ReadApi(book, chapters: chapters, loader: (c) async {
        started.add(c.index);
        if (c.index == 5) throw StateError('下载失败');
        if (c.index == 6) return ChapterContent.fromText('  ');
        return ChapterContent.fromText('${c.name}正文');
      });
      await api.bookContent.saveToLocal(book.bookUrl, 4, '已缓存');
      final progress = <String>[];
      final res = await CacheBook(api).cacheRange(7, 0, onProgress: (d, t, i) => progress.add('$d/$t'));
      expect(res.cached, [0, 3, 7]);
      expect(res.skipped, [1, 2, 4]);
      expect(res.failed.keys.toSet(), {5, 6});
      expect(res.failed[6], '正文为空');
      expect(started.contains(4), isFalse);
      expect(progress.length, 5);
      expect(progress.last, '5/5');
      expect(await api.bookContent.readFromLocal(book.bookUrl, 3), '第4章正文');
      expect(CacheBook.isRunning(book.bookUrl), isFalse);
    });

    test('a second task for the same book is refused while one runs; cancel stops early', () async {
      final book = _webBook();
      final gate = Completer<void>();
      final api = ReadApi(book, chapters: _chapters(6), loader: (c) async {
        await gate.future;
        return ChapterContent.fromText('x${c.index}');
      });
      final first = CacheBook(api, concurrent: 1).cacheRange(0, 5, isCancelled: () => gate.isCompleted && api.bookContent.existsSync(book.bookUrl, 1));
      await Future<void>.delayed(Duration.zero);
      expect(CacheBook.isRunning(book.bookUrl), isTrue);
      await expectLater(CacheBook(api).cacheRange(0, 1), throwsA(isA<StateError>().having((e) => e.message, 'message', '已有缓存任务正在进行中')));
      gate.complete();
      final res = await first;
      expect(res.cancelled, isTrue);
      expect(res.cached.length, lessThan(6));
    });

    test('local books have nothing to download', () async {
      final book = Book(bookUrl: 'books/a.txt', origin: ReadApi.localOrigin);
      final api = ReadApi(book, chapters: _chapters(3), loader: (c) async => throw StateError('must not be called'));
      final res = await CacheBook(api).cacheRange(0, 2);
      expect(res.cached, isEmpty);
      expect(res.skipped, [0, 1, 2]);
    });
  });
}
