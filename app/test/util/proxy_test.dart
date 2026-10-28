import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/http.dart';
import 'package:newread/util/legado/proxy.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_url.dart';

/// Minimal SOCKS5 server: no-auth or user/password, CONNECT by domain name; every target goes to [target] (records the names).
class FakeSocks5 {
  final ServerSocket server;
  final int target;
  final List<String> targets = [];
  final List<String> auths = [];
  FakeSocks5._(this.server, this.target);

  static Future<FakeSocks5> start(int target) async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final f = FakeSocks5._(s, target);
    s.listen(f._handle);
    return f;
  }

  Future<void> _handle(Socket c) async {
    final it = StreamIterator<Uint8List>(c);
    final buf = <int>[];
    Future<List<int>> read(int n) async {
      while (buf.length < n) {
        if (!await it.moveNext()) throw StateError('closed');
        buf.addAll(it.current);
      }
      final out = buf.sublist(0, n);
      buf.removeRange(0, n);
      return out;
    }

    final hello = await read(2);
    final methods = await read(hello[1]);
    if (methods.contains(2)) {
      c.add([5, 2]);
      await read(1);
      final ul = (await read(1))[0];
      final u = utf8.decode(await read(ul));
      final pl = (await read(1))[0];
      final p = utf8.decode(await read(pl));
      auths.add('$u:$p');
      c.add([1, 0]);
    } else {
      c.add([5, 0]);
    }
    final req = await read(4);
    final len = (await read(1))[0];
    final host = utf8.decode(await read(len));
    final pb = await read(2);
    targets.add('$host:${(pb[0] << 8) | pb[1]}');
    expect(req[3], 3);
    final up = await Socket.connect(InternetAddress.loopbackIPv4, target);
    c.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
    if (buf.isNotEmpty) up.add(buf);
    unawaited(up.cast<List<int>>().pipe(c).catchError((_) {}));
    unawaited(() async {
      while (await it.moveNext()) {
        up.add(it.current);
      }
      await up.close();
    }());
  }
}

void main() {
  late HttpServer origin;
  late HttpServer httpProxy;
  final proxied = <String>[];

  setUpAll(() async {
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((r) {
      r.response.headers.contentType = ContentType.text;
      r.response.write('origin ${r.headers.value('host')} ${r.uri.path}');
      r.response.close();
    });
    httpProxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    httpProxy.listen((r) {
      proxied.add('${r.uri}|${r.headers.value('proxy-authorization') ?? ''}');
      r.response.write('via proxy ${r.uri.host}${r.uri.path}');
      r.response.close();
    });
  });

  tearDownAll(() async {
    await origin.close(force: true);
    await httpProxy.close(force: true);
    await SocksBridge.closeAll();
    AppHttp.reset();
  });

  test('Legado proxy strings', () {
    final a = ProxySpec.parse('socks5://127.0.0.1:1080@user@pa:ss')!;
    expect([a.type, a.host, a.port, a.user, a.password], ['socks5', '127.0.0.1', 1080, 'user', 'pa:ss']);
    final b = ProxySpec.parse('http://10.0.0.2:8080')!;
    expect([b.type, b.host, b.port, b.user], ['http', '10.0.0.2', 8080, '']);
    expect(ProxySpec.parse('ftp://x:21'), isNull);
  });

  test('url option `proxy` with an HTTP proxy; `proxy` header of the source is not sent as a header', () async {
    final au = await AnalyzeUrl.create('http://books.example/a,{"proxy":"http://127.0.0.1:${httpProxy.port}"}');
    expect(au.proxy, 'http://127.0.0.1:${httpProxy.port}');
    expect((await au.getStrResponse()).body, 'via proxy books.example/a');
    final au2 = await AnalyzeUrl.create('http://books.example/b', headerMapF: {'proxy': 'http://127.0.0.1:${httpProxy.port}', 'X-A': '1'});
    expect(au2.headerMap.containsKey('proxy'), isFalse);
    expect((await au2.getStrResponse()).body, 'via proxy books.example/b');
    expect(proxied.length, 2);
  });

  test('SOCKS5 proxy with credentials (through the loopback bridge)', () async {
    final socks = await FakeSocks5.start(origin.port);
    try {
      final au = await AnalyzeUrl.create('http://books.example:8123/c?x=1,{"proxy":"socks5://127.0.0.1:${socks.server.port}@me@secret"}');
      final body = (await au.getStrResponse()).body;
      expect(body, 'origin books.example:8123 /c');
      expect(socks.targets, ['books.example:8123']);
      expect(socks.auths, ['me:secret']);
      // a second host through the same proxy opens a new tunnel
      final au2 = await AnalyzeUrl.create('http://other.example/d,{"proxy":"socks5://127.0.0.1:${socks.server.port}@me@secret"}');
      expect((await au2.getStrResponse()).body, 'origin other.example /d');
      expect(socks.targets, ['books.example:8123', 'other.example:80']);
    } finally {
      await socks.server.close();
    }
  });
}
