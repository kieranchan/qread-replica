import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/models/book.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

Book book(String url, String name, {String author = '', String group = '', int read = 0, int latest = 0, String origin = 'https://src.example'}) =>
    Book(bookUrl: url, name: name, author: author, bookgroup: group, durChapterTime: read, latestChapterTime: latest, origin: origin, kind: '玄幻');

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
    Bookdata.autoSync = false;
  });
  tearDown(() => dev.delete());

  Future<void> reload() async {
    Bookdata.reset();
    Groupdata.reset();
    await BookSelfN.load();
  }

  group('shelf basics', () {
    test('add stores a copy, persists as JSON under `bookself` and survives a reload', () async {
      final src = book('u1', '斗破苍穹', author: '土豆');
      final added = await BookSelfN.add(src);
      expect(identical(added, src), isFalse);
      src.name = 'mutated after add';
      expect(BookSelfN.get('u1')!.name, '斗破苍穹');
      await BookSelfN.add(book('u2', '凡人修仙传'));
      final stored = jsonDecode(await Storage.read('bookself')) as List;
      expect(stored.map((e) => (e as Map)['name']), ['斗破苍穹', '凡人修仙传']);
      expect((stored.first as Map)['bookUrl'], 'u1');

      await reload();
      expect(BookSelfN.books.map((b) => b.bookUrl), ['u1', 'u2']);
      expect(BookSelfN.contains('u2'), isTrue);
      expect(BookSelfN.contains('zzz'), isFalse);
      expect(BookSelfN.get('u1')!.author, '土豆');
    });

    test('adding the same book twice keeps one entry, its progress and group, and refreshes info', () async {
      await BookSelfN.add(book('u1', '书', group: '精品'));
      await BookSelfN.updateProgress('u1', index: 5, pos: 0.5, title: '第五章');
      final again = Book(bookUrl: 'u1', name: '书', coverUrl: 'c.jpg', intro: '简介', tocUrl: 't');
      final merged = await BookSelfN.add(again);
      expect(BookSelfN.books.length, 1);
      expect(merged.bookgroup, '精品');
      expect(merged.durChapterIndex, 5);
      expect((merged.coverUrl, merged.intro, merged.tocUrl, merged.isinfo), ('c.jpg', '简介', 't', true));
      expect(merged.kind, '玄幻'); // empty new value does not erase the old one
    });

    test('local books are identified by name + author, not by their device path', () async {
      final a = book('/Documents/books/a.txt', '本地书', author: '我', origin: kPhoneBook);
      final b = book('/var/other/a.txt', '本地书', author: '我', origin: kPhoneBook);
      final c = book('/var/other/c.txt', '本地书', author: '别人', origin: kPhoneBook);
      expect(bookKey(a), bookKey(b));
      expect(bookKey(a), isNot(bookKey(c)));
      expect(bookKey(book('u', 'n')), 'u');
      expect(await BookSelfN.addAll([a, b, c]), 2);
    });

    test('remove / removeMany / move', () async {
      await BookSelfN.addAll([book('a', 'A'), book('b', 'B'), book('c', 'C'), book('d', 'D')]);
      expect(await BookSelfN.remove('b'), isTrue);
      expect(await BookSelfN.remove('b'), isFalse);
      expect(await BookSelfN.removeMany(['a', 'zzz']), 1);
      expect(BookSelfN.books.map((b) => b.bookUrl), ['c', 'd']);
      await BookSelfN.move(1, 0);
      expect(BookSelfN.books.map((b) => b.bookUrl), ['d', 'c']);
      await reload();
      expect(BookSelfN.books.map((b) => b.bookUrl), ['d', 'c']);
    });

    test('revision changes on every mutation so lists rebuild', () async {
      final r0 = BookSelfN.revision.value;
      await BookSelfN.add(book('a', 'A'));
      final r1 = BookSelfN.revision.value;
      await BookSelfN.setGroup('a', 'x');
      expect(r1, greaterThan(r0));
      expect(BookSelfN.revision.value, greaterThan(r1));
    });
  });

  group('reading progress and update flags', () {
    test('updateProgress stores index / pos / title, stamps durChapterTime, clears the red mark and notifies listeners', () async {
      await BookSelfN.add(book('a', 'A')..isredupdate = true);
      final seen = <String>[];
      BookSelfN.notifyListenerlist[1] = (b) async => seen.add('${b.bookUrl}:${b.durChapterIndex}');
      final before = DateTime.now().millisecondsSinceEpoch;
      await BookSelfN.updateProgress('a', index: 7, pos: 12.5, title: '第七章', readchapter: '1,2,3');
      final b = BookSelfN.get('a')!;
      expect((b.durChapterIndex, b.durChapterPos, b.durChapterTitle, b.readchapter), (7, 12.5, '第七章', '1,2,3'));
      expect(b.durChapterTime, greaterThanOrEqualTo(before));
      expect(b.isredupdate, isFalse);
      expect(seen, ['a:7']);
      await BookSelfN.updateProgress('missing', index: 1, pos: 0); // unknown book: nothing happens, no notification
      expect(seen.length, 1);
      await reload();
      expect(BookSelfN.get('a')!.durChapterIndex, 7);
      expect(BookSelfN.lastRead?.bookUrl, 'a');
    });

    test('updateLatest marks a new chapter once; same title only refreshes lastCheckTime', () async {
      await BookSelfN.add(book('a', 'A'));
      expect(await BookSelfN.updateLatest('a', latestTitle: '第100章', totalChapters: 100), isTrue);
      var b = BookSelfN.get('a')!;
      expect((b.latestChapterTitle, b.totalChapterNum, b.isredupdate), ('第100章', 100, true));
      expect(b.latestChapterTime, greaterThan(0));
      expect(b.lastCheckTime, greaterThan(0));
      final t = b.latestChapterTime;
      await BookSelfN.clearRedUpdate(bookUrl: 'a');
      expect(await BookSelfN.updateLatest('a', latestTitle: '第100章', totalChapters: 101), isFalse);
      b = BookSelfN.get('a')!;
      expect((b.isredupdate, b.latestChapterTime, b.totalChapterNum), (false, t, 101));
      expect(await BookSelfN.updateLatest('nope', latestTitle: 'x', totalChapters: 1), isFalse);
    });

    test('field setters: group, type, flags, basic info, toc', () async {
      await BookSelfN.add(book('a', 'A'));
      await BookSelfN.setGroup('a', '精品');
      await BookSelfN.setType('a', 2, coverUrl: 'cov');
      await BookSelfN.setUpdate('a', true);
      await BookSelfN.setReverseCatalog('a', true);
      await BookSelfN.setUseReplaceRule('a', true);
      await BookSelfN.setUseAi('a', true);
      await BookSelfN.setBasic('a', name: '新名', intro: '新简介');
      await BookSelfN.updateToc('a', charset: 'gbk', tocUrl: 'tt', durTitle: 'd', latestTitle: 'l', totalChapters: 9);
      await reload();
      final b = BookSelfN.get('a')!;
      expect((b.bookgroup, b.type_, b.coverUrl, b.update, b.reverseCatalog, b.useReplaceRule, b.useai), ('精品', 2, 'cov', true, true, true, true));
      expect((b.name, b.intro, b.charset, b.tocUrl, b.durChapterTitle, b.latestChapterTitle, b.totalChapterNum), ('新名', '新简介', 'gbk', 'tt', 'd', 'l', 9));
      await BookSelfN.setGroup('a', kAllGroup); // the implicit group means "no group"
      expect(BookSelfN.get('a')!.bookgroup, '');
    });

    test('updateInfo fills only non-empty fields and flags isinfo', () async {
      await BookSelfN.add(book('a', 'A'));
      await BookSelfN.updateInfo(Book(bookUrl: 'a', kind: '', coverUrl: 'c', intro: '', tocUrl: 'toc', wordCount: '100万字', origin: 'src2', isqread: true));
      final b = BookSelfN.get('a')!;
      expect((b.kind, b.coverUrl, b.intro, b.tocUrl, b.wordCount, b.origin, b.isqread, b.isinfo), ('玄幻', 'c', '', 'toc', '100万字', 'src2', true, true));
    });
  });

  group('groups', () {
    test('add rejects empty, reserved and duplicate names; order, hide and persistence', () async {
      expect(await Groupdata.add('  '), isFalse);
      expect(await Groupdata.add(kAllGroup), isFalse);
      expect(await Groupdata.add('玄幻'), isTrue);
      expect(await Groupdata.add('玄幻'), isFalse);
      await Groupdata.add('都市');
      await Groupdata.add('历史');
      await Groupdata.move(2, 0);
      expect(Groupdata.groups, ['历史', '玄幻', '都市']);
      await Groupdata.setHidden('玄幻', true);
      expect(Groupdata.visible, [kAllGroup, '历史', '都市']);
      expect(Groupdata.isHidden('玄幻'), isTrue);
      expect(Groupdata.contains('都市'), isTrue);
      expect(jsonDecode(await Storage.read('bookgroup')), ['历史', '玄幻', '都市']);
      expect(jsonDecode(await Storage.read('hidegroups')), ['玄幻']);

      await reload();
      expect(Groupdata.groups, ['历史', '玄幻', '都市']);
      expect(Groupdata.hidegroups, ['玄幻']);
      await Groupdata.setHidden('玄幻', false);
      expect(Groupdata.hidegroups, isEmpty);
    });

    test('books follow group rename and removal; membership supports several groups per book and 「全部」', () async {
      await Groupdata.add('玄幻');
      await BookSelfN.addAll([book('a', 'A', group: '玄幻'), book('b', 'B', group: '玄幻,精品'), book('c', 'C')]);
      expect(BookSelfN.booksOf('玄幻').map((b) => b.name), ['A', 'B']);
      expect(BookSelfN.booksOf('精品').map((b) => b.name), ['B']);
      expect(BookSelfN.booksOf('').map((b) => b.name), ['C']);
      expect(BookSelfN.booksOf(kAllGroup).length, 3);
      expect(BookSelfN.groupCounts(), {kAllGroup: 3, '玄幻': 2});

      expect(await Groupdata.rename('玄幻', '仙侠'), isTrue);
      expect(Groupdata.groups, ['仙侠']);
      expect(BookSelfN.booksOf('仙侠').map((b) => b.name), ['A', 'B']);
      expect(BookSelfN.get('b')!.bookgroup, '仙侠,精品');
      expect(await Groupdata.rename('不存在', 'x'), isFalse);

      await Groupdata.setHidden('仙侠', true);
      await Groupdata.remove('仙侠');
      expect(Groupdata.groups, isEmpty);
      expect(Groupdata.hidegroups, isEmpty);
      expect(BookSelfN.get('a')!.bookgroup, '');
      expect(BookSelfN.get('b')!.bookgroup, '精品');

      await BookSelfN.setGroupMany(['a', 'c'], '合集');
      expect(BookSelfN.booksOf('合集').map((b) => b.name), ['A', 'C']);
    });
  });

  group('sorting', () {
    test('recent read, recent update, name, author and manual order; ties keep the stored order', () async {
      await BookSelfN.addAll([
        book('a', 'banana', author: 'z', read: 30, latest: 5),
        book('b', 'apple', author: 'y', read: 10, latest: 50),
        book('c', 'cherry', author: 'x', read: 20, latest: 50),
        book('d', 'date', author: 'x', read: 0, latest: 0),
      ]);
      List<String> order(BookSort s, {bool reverse = false}) => BookSelfN.booksOf(kAllGroup, sort: s, reverse: reverse).map((b) => b.bookUrl).toList();
      expect(order(BookSort.manual), ['a', 'b', 'c', 'd']);
      expect(order(BookSort.recentRead), ['a', 'c', 'b', 'd']);
      expect(order(BookSort.recentUpdate), ['b', 'c', 'a', 'd']); // b and c tie: stored order
      expect(order(BookSort.name), ['b', 'a', 'c', 'd']);
      expect(order(BookSort.author), ['c', 'd', 'b', 'a']); // c and d tie: stored order
      expect(order(BookSort.name, reverse: true), ['d', 'c', 'a', 'b']);
      expect(BookSelfN.lastRead?.bookUrl, 'a');
    });
  });
}
