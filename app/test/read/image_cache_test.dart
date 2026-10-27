// util/image + util/cahce: caches, url options, disk cache with a local HTTP server (no binding: the widget-test binding mocks dart:io HTTP).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/util/cahce/imagecache.dart';
import 'package:newread/util/cahce/searchcache.dart';
import 'package:newread/util/image/cache.dart';
import 'package:newread/util/image/image_book_manger.dart';
import 'package:newread/util/image/image_cache_manger.dart';
import 'package:newread/util/image/image_error.dart';
import 'package:newread/util/image/image_service.dart';
import 'package:newread/util/image/image_size.dart';

import 'support/fixtures.dart';

void main() {
  late Directory tmp;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_img_');
    ReadStorageRoot.dir = tmp;
    Imagecache.clear();
    Imagecache2.clear();
    Imagecache3.clear();
    ImageCache.clear();
    ImageError.clear();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('byte caches evict the least recently used entries by total size', () {
    for (var i = 0; i < 100; i++) {
      Imagecache.put('u$i', Uint8List(1024 * 1024)); // 100 MB in total, the cache holds 64 MB
    }
    expect(Imagecache.totalBytes, lessThanOrEqualTo(64 * 1024 * 1024));
    expect(Imagecache.get('u0'), isNull);
    expect(Imagecache.get('u99'), isNotNull);
    Imagecache.put('huge', Uint8List(65 * 1024 * 1024)); // larger than the cache: not stored
    expect(Imagecache.get('huge'), isNull);
    Imagecache2.put('k', Uint8List(3));
    expect(Imagecache2.get('k'), hasLength(3));
  });

  test('path cache: bounded, refreshed on read', () {
    for (var i = 0; i < Imagecache3.maxEntries + 10; i++) {
      Imagecache3.put('u$i', '/p/$i');
    }
    expect(Imagecache3.length, Imagecache3.maxEntries);
    expect(Imagecache3.get('u0'), isNull);
    expect(Imagecache3.get('u${Imagecache3.maxEntries + 9}'), '/p/${Imagecache3.maxEntries + 9}');
  });

  test('SearchCache expires entries', () {
    var now = DateTime(2026, 1, 1);
    final cache = SearchCache(ttl: const Duration(minutes: 5), now: () => now);
    cache.put('q', [1, 2, 3]);
    expect(cache.get('q'), [1, 2, 3]);
    now = now.add(const Duration(minutes: 4));
    expect(cache.get('q'), isNotNull);
    cache.put('old', [9]);
    now = now.add(const Duration(minutes: 3));
    expect(cache.get('q'), isNull);
    expect(cache.length, 1);
    cache.clearExpired();
    expect(cache.get('old'), [9]);
  });

  test('ImageError remembers failures', () {
    ImageError.mark('http://x/a.png', '404');
    expect(ImageError.failed('http://x/a.png'), isTrue);
    expect(ImageError.messageOf('http://x/a.png'), '404');
    ImageError.clear('http://x/a.png');
    expect(ImageError.failed('http://x/a.png'), isFalse);
  });

  test('HeaderUrl and url resolution', () {
    final u = HeaderUrl.parse('http://h/a.png,{"headers":{"Referer":"http://h/","X-A":1}}');
    expect(u.url, 'http://h/a.png');
    expect(u.headers, {'Referer': 'http://h/', 'X-A': '1'});
    expect(HeaderUrl.parse('http://h/b.png').headers, isEmpty);
    expect(HeaderUrl.parse('http://h/c.png,{broken').url, 'http://h/c.png'); // broken options are dropped
    expect(ImageBookManger.resolveUrl('http://h/book/ch1.html', '../img/a.png'), 'http://h/img/a.png');
    expect(ImageBookManger.resolveUrl('http://h/book/ch1.html', '/img/a.png'), 'http://h/img/a.png');
    expect(ImageBookManger.resolveUrl('http://h/x', 'https://o/a.png,{"headers":{}}'), 'https://o/a.png,{"headers":{}}');
    expect(ImageBookManger.resolveUrl('http://h/x', 'data:image/png;base64,AA'), 'data:image/png;base64,AA');
  });

  test('disk cache downloads once with the source headers and survives a failing server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var hits = 0;
    final seenReferers = <String?>[];
    server.listen((req) {
      hits++;
      seenReferers.add(req.headers.value('referer'));
      if (req.uri.path == '/ok.png') {
        req.response.add(pngHeader(40, 20));
      } else {
        req.response.statusCode = 404;
      }
      req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';

    final f = await ImgCacheManger.fileFor('$base/ok.png,{"headers":{"Referer":"http://src/"}}');
    expect(f, isNotNull);
    expect(f!.path, endsWith('.png'));
    expect(ImageSizeReader.fromFile(f), const Size(40, 20));
    expect(f.path, contains(ReadFileStore.md5Hex('$base/ok.png')));
    expect(seenReferers.single, 'http://src/');

    // second call: memory/disk cache, no request
    await ImgCacheManger.fileFor('$base/ok.png');
    Imagecache3.clear();
    await ImgCacheManger.fileFor('$base/ok.png');
    expect(hits, 1);

    expect(await ImgCacheManger.fileFor('$base/missing.png'), isNull);
    final bytes = await ImgCacheManger.bytesFor('$base/ok.png');
    expect(bytes, hasLength(pngHeader(40, 20).length));

    // helper on top of it: relative image of a chapter
    final viaBook = await ImageBookManger.imageFile('$base/book/ch.html', '/ok.png');
    expect(viaBook!.path.replaceAll(r'\', '/'), f.path.replaceAll(r'\', '/'));

    ImgCacheManger.maxBytes = 1;
    expect(ImgCacheManger.trim(), 1);
    ImgCacheManger.maxBytes = 300 * 1024 * 1024;
    await ImgCacheManger.clear();
    expect(ImgCacheManger.dir.existsSync(), isFalse);
  });

  test('ImageService reads sizes in a batch and fills the size cache', () async {
    final a = File('${tmp.path}/a.png')..writeAsBytesSync(pngHeader(10, 20));
    final b = File('${tmp.path}/b.png')..writeAsBytesSync(pngHeader(30, 40));
    final sizes = await ImageService.readSizes([a.path, b.path, '${tmp.path}/none.png']);
    expect(sizes[a.path], const Size(10, 20));
    expect(sizes[b.path], const Size(30, 40));
    expect(sizes.length, 2);
    expect(ImageCache.sizes[a.path], const Size(10, 20));
    // second call is served from the cache (file may be gone)
    a.deleteSync();
    expect((await ImageService.readSizes([a.path]))[a.path], const Size(10, 20));
    expect(await ImageSizeReader.resolve(b.path), const Size(30, 40));
  });

  test('size cache is bounded', () {
    for (var i = 0; i < ImageCache.maxEntries + 5; i++) {
      ImageCache.sizes['k$i'] = const Size(1, 1);
    }
    expect(ImageCache.sizes.length, ImageCache.maxEntries);
    expect(ImageCache.sizes['k0'], isNull);
  });
}
