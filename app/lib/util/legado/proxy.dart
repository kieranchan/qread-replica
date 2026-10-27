// util/legado/proxy.dart - the per-request `proxy` of a url rule (`url,{"proxy":"socks5://127.0.0.1:1080"}` or a `proxy` header).
//
// The original parses the option into AnalyzeUrl (0xe3340c stores `proxy`) but its HttpClient keeps the environment proxy
// (`findProxyFromEnvironment` is the only proxy resolver in the snapshot). The replica applies it with Legado's syntax
// (`getProxyClient`): `http|socks4|socks5://host:port[@user@password]`.
// HTTP proxies use HttpClient's own support (`PROXY host:port` + basic credentials). dart:io has no SOCKS client, so a SOCKS proxy is
// reached through a small loopback bridge that speaks HTTP-proxy to the HttpClient (CONNECT for https, absolute-URI requests for http)
// and SOCKS4a/SOCKS5 to the real proxy; proxied clients do not keep connections alive, so a bridged connection carries one target.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProxySpec {
  final String type; // http | socks4 | socks5
  final String host;
  final int port;
  final String user;
  final String password;

  const ProxySpec(this.type, this.host, this.port, {this.user = '', this.password = ''});

  static final RegExp _re = RegExp(r'(http|socks4|socks5)://(.*):(\d{2,5})(@.*@.*)?');

  /// Legado's regex; null when [s] is not a proxy string.
  static ProxySpec? parse(String s) {
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    var user = '', pass = '';
    final auth = m.group(4);
    if (auth != null && auth.isNotEmpty) {
      final parts = auth.split('@');
      if (parts.length > 2) {
        user = parts[1];
        pass = parts[2];
      }
    }
    return ProxySpec(m.group(1)!, m.group(2)!, int.parse(m.group(3)!), user: user, password: pass);
  }

  @override
  String toString() => '$type://$host:$port';

  /// The `HttpClient.findProxy` answer for this proxy (for SOCKS: the loopback bridge, started on first use).
  Future<String> findProxyRule() async {
    if (type == 'http') return 'PROXY $host:$port';
    final bridge = await SocksBridge.forSpec(this);
    return 'PROXY 127.0.0.1:${bridge.port}';
  }

  /// Points [c] at this proxy ([rule] from [findProxyRule]) with the HTTP proxy's credentials.
  void configure(HttpClient c, String rule) {
    c.findProxy = (_) => rule;
    if (type == 'http' && user.isNotEmpty) c.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, password));
  }

  /// Opens a connection to [targetHost]:[targetPort] through this SOCKS proxy. The returned reader holds bytes read past the reply.
  Future<(Socket, StreamIterator<Uint8List>, List<int>)> socksConnect(String targetHost, int targetPort) async {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 20));
    final it = StreamIterator<Uint8List>(s);
    final buf = <int>[];
    Future<List<int>> read(int n) async {
      while (buf.length < n) {
        if (!await it.moveNext().timeout(const Duration(seconds: 20))) throw const SocketException('proxy closed the connection');
        buf.addAll(it.current);
      }
      final out = buf.sublist(0, n);
      buf.removeRange(0, n);
      return out;
    }

    try {
      if (type == 'socks4') {
        // SOCKS4a: destination IP 0.0.0.1 + host name
        s.add([4, 1, targetPort >> 8, targetPort & 0xff, 0, 0, 0, 1, ...utf8.encode(user), 0, ...utf8.encode(targetHost), 0]);
        final r = await read(8);
        if (r[1] != 0x5a) throw SocketException('SOCKS4 proxy refused the connection (${r[1]})');
        return (s, it, buf);
      }
      final methods = user.isNotEmpty ? [0, 2] : [0];
      s.add([5, methods.length, ...methods]);
      final m = await read(2);
      if (m[1] == 2) {
        final u = utf8.encode(user), p = utf8.encode(password);
        s.add([1, u.length, ...u, p.length, ...p]);
        final a = await read(2);
        if (a[1] != 0) throw const SocketException('SOCKS5 proxy authentication failed');
      } else if (m[1] != 0) {
        throw const SocketException('SOCKS5 proxy: no acceptable authentication method');
      }
      final h = utf8.encode(targetHost);
      s.add([5, 1, 0, 3, h.length, ...h, targetPort >> 8, targetPort & 0xff]);
      final head = await read(4);
      if (head[1] != 0) throw SocketException('SOCKS5 proxy refused the connection (${head[1]})');
      final atyp = head[3];
      final addrLen = atyp == 1 ? 4 : (atyp == 4 ? 16 : (await read(1))[0]);
      await read(addrLen + 2);
      return (s, it, buf);
    } catch (_) {
      s.destroy();
      rethrow;
    }
  }
}

/// Loopback HTTP proxy that forwards through a SOCKS proxy (one bridge per proxy string, alive for the process).
class SocksBridge {
  final ProxySpec spec;
  final ServerSocket _server;
  SocksBridge._(this.spec, this._server);

  int get port => _server.port;

  static final Map<String, Future<SocksBridge>> _bridges = {};

  static Future<SocksBridge> forSpec(ProxySpec spec) => _bridges[
          '${spec.type}|${spec.host}|${spec.port}|${spec.user}|${spec.password}'] ??=
      ServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((srv) {
        final b = SocksBridge._(spec, srv);
        srv.listen(b._handle);
        return b;
      });

  /// Closes every bridge (tests).
  static Future<void> closeAll() async {
    final all = _bridges.values.toList();
    _bridges.clear();
    for (final f in all) {
      await (await f)._server.close();
    }
  }

  Future<void> _handle(Socket client) async {
    final it = StreamIterator<Uint8List>(client);
    final head = <int>[];
    var end = -1;
    try {
      while (end < 0) {
        if (!await it.moveNext()) {
          client.destroy();
          return;
        }
        head.addAll(it.current);
        end = _headerEnd(head);
        if (head.length > 65536) throw const FormatException('header too large');
      }
      final text = latin1.decode(head.sublist(0, end));
      final firstLine = text.split('\r\n').first;
      final parts = firstLine.split(' ');
      if (parts.length < 3) throw const FormatException('bad request line');
      final method = parts[0];
      String targetHost;
      int targetPort;
      List<int> firstBytes;
      if (method == 'CONNECT') {
        final hp = parts[1];
        final i = hp.lastIndexOf(':');
        targetHost = hp.substring(0, i);
        targetPort = int.parse(hp.substring(i + 1));
        firstBytes = head.sublist(end + 4);
      } else {
        final u = Uri.parse(parts[1]);
        targetHost = u.host;
        targetPort = u.hasPort ? u.port : 80;
        final path = '${u.path.isEmpty ? '/' : u.path}${u.hasQuery ? '?${u.query}' : ''}';
        final rest = text.substring(firstLine.length);
        firstBytes = [...latin1.encode('$method $path ${parts[2]}$rest'), ...head.sublist(end)];
      }
      if (targetHost.startsWith('[') && targetHost.endsWith(']')) targetHost = targetHost.substring(1, targetHost.length - 1);
      final (upstream, upIt, ahead) = await spec.socksConnect(targetHost, targetPort);
      if (method == 'CONNECT') client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      if (firstBytes.isNotEmpty) upstream.add(firstBytes);
      if (ahead.isNotEmpty) client.add(ahead);
      unawaited(_pipe(upIt, client));
      unawaited(_pipe(it, upstream));
    } catch (e) {
      try {
        client.add(latin1.encode('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
        await client.close();
      } catch (_) {}
      client.destroy();
    }
  }

  static int _headerEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
    }
    return -1;
  }

  static Future<void> _pipe(StreamIterator<Uint8List> from, Socket to) async {
    try {
      while (await from.moveNext()) {
        to.add(from.current);
      }
      await to.close();
    } catch (_) {
      to.destroy();
    }
  }
}
