import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/userapi.dart' show CloudKind;
import 'package:newread/data/bookself.dart';
import 'package:newread/data/cloud_api.dart';
import 'package:newread/data/cloud_sync.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';
import '../support/fake_cloud.dart';

Book book(String url, String name, {int read = 0, int idx = 0, String group = '', int total = 0, int latest = 0, int check = 0}) => Book(
    bookUrl: url, name: name, durChapterTime: read, durChapterIndex: idx, bookgroup: group, totalChapterNum: total, latestChapterTime: latest, lastCheckTime: check, origin: 'https://s.example');

void main() {
  late FakeCloud cloud;
  late TestDevice a;
  late TestDevice b;

  Future<void> use(TestDevice d) async {
    await d.activate();
    Bookdata.autoSync = false;
    UserSession.isLoggedIn = true;
    UserSession.cloudbookself = true;
  }

  Future<void> leave(TestDevice d) async => d.capture();

  setUp(() async {
    cloud = FakeCloud();
    a = await newDevice();
    b = await newDevice();
    await use(a);
  });
  tearDown(() {
    a.delete();
    b.delete();
    UserSession.isLoggedIn = false;
    UserSession.cloudbookself = false;
    Bookdata.autoSync = true;
    defaultCloudApi = const UserApiCloud();
  });

  test('switch off: nothing is called', () async {
    UserSession.cloudbookself = false;
    await BookSelfN.add(book('u1', 'A'));
    expect(await BookSelfN.syncCloud(api: cloud), isNull);
    expect((cloud.updateCalls, cloud.uploads), (0, 0));
  });

  test('first sync uploads the shelf, stores the etag and the time; an unchanged shelf is not uploaded again', () async {
    await BookSelfN.addAll([book('u1', 'A'), book('u2', 'B')]);
    final r = await BookSelfN.syncCloud(api: cloud);
    expect((r!.pushed, r.pulled), (true, false));
    expect(cloud.books().map((m) => m['bookUrl']), ['u1', 'u2']);
    expect(Storage.getString(PrefKeys.etag), md5Of(cloud.lists[CloudKind.books]!));
    expect(Storage.getString(PrefKeys.lastSyncTime), matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$')));
    expect(cloud.uploads, 1);

    final again = await BookSelfN.syncCloud(api: cloud);
    expect(again!.nothingToDo, isTrue);
    // the first sync listed the (empty) cloud once, as the original does when the update-url answer is ''; the second one is current
    expect((cloud.uploads, cloud.listCalls), (1, 1));

    // a local change is pushed without downloading anything
    await BookSelfN.setGroup('u1', 'x');
    final third = await BookSelfN.syncCloud(api: cloud);
    expect((third!.pushed, third.pulled), (true, false));
    expect(cloud.books().first['bookgroup'], 'x');
    expect((cloud.uploads, cloud.listCalls), (2, 1));
  });

  test('a second device pulls the shelf; merging identical data does not upload again', () async {
    await BookSelfN.addAll([book('u1', 'A', read: 5, idx: 3), book('u2', 'B')]);
    await BookSelfN.syncCloud(api: cloud);
    await leave(a);

    await use(b);
    final r = await BookSelfN.syncCloud(api: cloud);
    expect((r!.pulled, r.pushed, r.localChanged), (true, false, true));
    expect(BookSelfN.books.map((x) => x.bookUrl), ['u1', 'u2']);
    expect(BookSelfN.get('u1')!.durChapterIndex, 3);
    expect(cloud.uploads, 1);
    // the merged shelf was saved locally
    Bookdata.reset();
    expect((await BookSelfN.load()).length, 2);
  });

  test('reading progress follows the later durChapterTime in both directions', () async {
    await BookSelfN.add(book('u1', 'A', read: 100, idx: 1));
    await BookSelfN.syncCloud(api: cloud);
    await leave(a);

    await use(b);
    await BookSelfN.syncCloud(api: cloud);
    // device B reads further (newer timestamp)
    await BookSelfN.updateProgress('u1', index: 9, pos: 3, title: '第九章');
    await BookSelfN.syncCloud(api: cloud);
    expect(cloud.books().single['durChapterIndex'], 9);
    await leave(b);

    // device A still has the old position; its own edit is older than what B stored, so the cloud position wins
    await use(a);
    await BookSelfN.load();
    final stale = BookSelfN.get('u1')!
      ..durChapterIndex = 2
      ..durChapterTime = 150;
    expect(stale.durChapterIndex, 2);
    await Bookdata.save(need: false);
    final r = await BookSelfN.syncCloud(api: cloud);
    expect((r!.pulled, r.pushed), (true, false));
    expect(BookSelfN.get('u1')!.durChapterIndex, 9);
    expect(BookSelfN.get('u1')!.durChapterTitle, '第九章');

    // A reads on: its position is newer, the cloud was not changed meanwhile, so A pushes without downloading
    await BookSelfN.updateProgress('u1', index: 12, pos: 0, title: '第十二章');
    final listCalls = cloud.listCalls;
    final r2 = await BookSelfN.syncCloud(api: cloud);
    expect((r2!.pushed, r2.pulled), (true, false));
    expect(cloud.listCalls, listCalls);
    expect(cloud.books().single['durChapterIndex'], 12);
    await leave(a);

    await use(b);
    await BookSelfN.syncCloud(api: cloud);
    expect(BookSelfN.get('u1')!.durChapterIndex, 12);
  });
  test('deletions propagate and are not resurrected; new books on both sides are kept', () async {
    await BookSelfN.addAll([book('x', 'X'), book('y', 'Y'), book('z', 'Z')]);
    await BookSelfN.syncCloud(api: cloud);
    await leave(a);

    await use(b);
    await BookSelfN.syncCloud(api: cloud); // b has x y z
    await BookSelfN.remove('y'); // deleted on b
    await BookSelfN.add(book('n-b', 'new on b'));
    await BookSelfN.syncCloud(api: cloud);
    expect(cloud.books().map((m) => m['bookUrl']), ['x', 'z', 'n-b']);
    await leave(b);

    // meanwhile device a (still having x y z) adds a book and deletes x, then syncs: it gets b's changes, keeps its own
    await use(a);
    await BookSelfN.add(book('n-a', 'new on a'));
    await BookSelfN.remove('x');
    final r = await BookSelfN.syncCloud(api: cloud);
    expect(r!.pulled && r.pushed, isTrue);
    expect(BookSelfN.books.map((x) => x.bookUrl).toSet(), {'z', 'n-a', 'n-b'});
    expect(cloud.books().map((m) => m['bookUrl']).toSet(), {'z', 'n-a', 'n-b'});
    await leave(a);

    await use(b);
    await BookSelfN.syncCloud(api: cloud);
    expect(BookSelfN.books.map((x) => x.bookUrl).toSet(), {'z', 'n-a', 'n-b'});
  });

  test('latest-chapter info follows the larger chapter count; lastCheckTime is the max; empty fields are filled', () async {
    final local = book('u', 'A', total: 10, latest: 100, check: 5)..latestChapterTitle = 'old';
    final remote = book('u', 'A', total: 12, latest: 90, check: 9)
      ..latestChapterTitle = 'newer'
      ..coverUrl = 'c.jpg'
      ..kind = '玄幻';
    final m = BookSelfN.mergeBooks(local, remote);
    expect((m.latestChapterTitle, m.totalChapterNum, m.latestChapterTime, m.lastCheckTime), ('newer', 12, 100, 9));
    expect((m.coverUrl, m.kind), ('c.jpg', '玄幻'));
    // local group and flags win
    final l2 = book('u', 'A', group: '本地');
    expect(BookSelfN.mergeBooks(l2, book('u', 'A', group: '云端')).bookgroup, '本地');
  });

  test('server failure: CloudSyncException, local shelf untouched', () async {
    await BookSelfN.add(book('u1', 'A'));
    cloud.failUpdate = true;
    await expectLater(BookSelfN.syncCloud(api: cloud), throwsA(isA<CloudSyncException>().having((e) => e.message, 'm', '获取云端信息失败')));
    expect(BookSelfN.books.length, 1);
    expect(cloud.uploads, 0);
    cloud.failUpdate = false;
    expect((await BookSelfN.syncCloud(api: cloud))!.pushed, isTrue);
  });

  test('logging in on a device with an old etag but an empty cloud re-uploads the shelf', () async {
    await BookSelfN.add(book('u1', 'A'));
    await Storage.setString(PrefKeys.etag, ''); // never synced with this account
    await Storage.setString('${PrefKeys.etag}.syncedmd5', md5Of(Bookdata.encode())); // stale marker from a previous account
    final r = await BookSelfN.syncCloud(api: cloud);
    expect(r!.pushed, isTrue);
    expect(cloud.books().length, 1);
  });

  test('the debounce timer syncs after a change when the switch is on (default cloud api is injectable)', () async {
    defaultCloudApi = cloud;
    Bookdata.autoSync = true;
    Bookdata.syncDelay = const Duration(milliseconds: 20);
    addTearDown(() => Bookdata.syncDelay = const Duration(seconds: 5));
    await BookSelfN.add(book('u1', 'A'));
    await BookSelfN.add(book('u2', 'B')); // restarts the timer: one upload for both
    expect(cloud.uploads, 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(cloud.uploads, 1);
    expect(cloud.books().length, 2);
    // switch off: no timer
    UserSession.cloudbookself = false;
    await BookSelfN.add(book('u3', 'C'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cloud.uploads, 1);
  });

  group('group list sync', () {
    test('groups travel through the cloud and deletions are not resurrected', () async {
      await Groupdata.add('玄幻');
      await Groupdata.add('都市');
      final r = await Groupdata.syncCloud(api: cloud);
      expect(r.pushed, isTrue);
      expect(jsonDecode(cloud.lists[CloudKind.groups]!), ['玄幻', '都市']);
      expect(Storage.getString(PrefKeys.grouptag), md5Of(cloud.lists[CloudKind.groups]!));
      await leave(a);

      await use(b);
      await Groupdata.syncCloud(api: cloud);
      expect(Groupdata.groups, ['玄幻', '都市']);
      await Groupdata.remove('都市');
      await Groupdata.add('历史');
      await Groupdata.syncCloud(api: cloud);
      expect(jsonDecode(cloud.lists[CloudKind.groups]!), ['玄幻', '历史']);
      await leave(b);

      await use(a);
      await Groupdata.syncCloud(api: cloud);
      expect(Groupdata.groups, ['玄幻', '历史']);
    });

    test('the implicit 「全部」 group coming from the cloud list is ignored', () async {
      cloud.lists[CloudKind.groups] = jsonEncode([kAllGroup, '玄幻']);
      await Groupdata.syncCloud(api: cloud);
      expect(Groupdata.groups, ['玄幻']);
    });
  });

  group('CloudSync.merge3', () {
    test('keeps local order, adds new remote items, drops items deleted on either side, resolves duplicates', () {
      final merged = CloudSync.merge3<String>(
        local: ['a', 'b', 'c', 'b'],
        remote: ['c', 'd', 'e', 'd'],
        key: (s) => s,
        base: {'a', 'e'},
      );
      // a: only local, in base -> deleted remotely; b: new local, kept once; c: both; d: new remote; e: only remote, in base -> deleted locally
      expect(merged, ['b', 'c', 'd']);
    });
  });
}
