// Source cookies survive a relaunch (owner, 2026-11-03: logged in to a source, asked to log in again now and then — the store was
// memory only and iOS ends the process every so often).
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/cookie_persist.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/legado/cookie_jar.dart';

import '../support/env.dart';

void main() {
  setUp(() async {
    await newDevice();
    CookieStore.resetForTests();
  });
  tearDown(CookieStore.resetForTests);

  test('cookies set, merged from responses and removed are written and come back after a relaunch', () async {
    await CookiePersist.init();
    CookieStore.setCookie('https://www.example.com/login', 'sid=abc');
    CookieStore.saveFromResponse('https://api.example.com/x', ['token=t1; Path=/']);
    CookieStore.setCookie('https://other.org/', 'u=1');
    await Future<void>.delayed(Duration.zero);
    expect(Storage.getString(CookiePersist.key), contains('sid=abc'));

    // the process ends: a fresh store loads what was written
    CookieStore.resetForTests();
    expect(CookieStore.getCookie('https://www.example.com/'), '');
    await CookiePersist.init();
    expect(CookieStore.getCookie('https://www.example.com/chapter/1'), 'sid=abc;token=t1');
    expect(CookieStore.getCookie('https://other.org/'), 'u=1');

    // a removal is written too
    CookieStore.removeCookie('https://other.org/');
    await Future<void>.delayed(Duration.zero);
    CookieStore.resetForTests();
    await CookiePersist.init();
    expect(CookieStore.getCookie('https://other.org/'), '');
    expect(CookieStore.getCookie('https://example.com/'), 'sid=abc;token=t1');
  });

  test('a damaged record is ignored', () async {
    await Storage.setString(CookiePersist.key, '{not json');
    await CookiePersist.init();
    expect(CookieStore.all, isEmpty);
    CookieStore.setCookie('https://a.com/', 'k=v');
    await Future<void>.delayed(Duration.zero);
    expect(Storage.getString(CookiePersist.key), '{"a.com":"k=v"}');
  });
}
