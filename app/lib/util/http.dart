// util/http.dart - the engine's HTTP transport: one replaceable Dio (tests and hosts swap it), manual redirects with cookie handling,
// gzip, retries, and charset handling (HTTP header, BOM, `<meta charset>`, UTF-8 validity, GBK/GB2312/GB18030, Big5).
//
// The original runs Dio inside a worker isolate (`httpIsolate`, `HttpRequest`/`HttpResponse` at 0xe2528); the replica keeps the same
// request/response value classes but runs on the calling isolate (rules are I/O bound, not CPU bound).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'legado/cjk_charsets.dart';
import 'legado/cookie_jar.dart';

class HttpRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
  final bool followRedirects;

  /// Send/receive the cookies of [CookieStore] and store `Set-Cookie` answers.
  final bool useCookieJar;
  final int retry;

  const HttpRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 30),
    this.followRedirects = true,
    this.useCookieJar = true,
    this.retry = 0,
  });
}

class HttpResponse {
  final int statusCode;
  final String statusMessage;

  /// Lower-cased header names.
  final Map<String, List<String>> headers;
  final Uint8List bodyBytes;

  /// Final URL after redirects.
  final String url;

  const HttpResponse(this.statusCode, this.statusMessage, this.headers, this.bodyBytes, this.url);

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
  String? header(String name) {
    final v = headers[name.toLowerCase()];
    return v == null || v.isEmpty ? null : v.first;
  }

  String? get contentType => header('content-type');
}

abstract class AppHttp {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// Value of the `User-Agent` header when a request has none (the original keeps it in `__NR_UA__`).
  static String userAgent = defaultUserAgent;

  /// Legado trusts every TLS certificate (book sites are often misconfigured).
  static bool allowBadCertificates = true;

  static Dio Function() dioBuilder = _defaultDio;
  static Dio? _dio;

  static Dio get dio => _dio ??= dioBuilder();

  /// Replaces the Dio instance (tests, hosts with their own interceptors/proxy).
  static void useDio(Dio d) => _dio = d;

  static void reset() => _dio = null;

  static Dio _defaultDio() {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.bytes,
      followRedirects: false,
      validateStatus: (_) => true,
      receiveDataWhenStatusError: true,
    ));
    d.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final c = HttpClient();
      if (allowBadCertificates) c.badCertificateCallback = (cert, host, port) => true;
      return c;
    });
    return d;
  }

  static const int maxRedirects = 10;

  /// Sends [r] and follows redirects (303/301/302 turn into GET, 307/308 keep method and body).
  static Future<HttpResponse> send(HttpRequest r) async {
    Object? lastError;
    HttpResponse? last;
    for (var attempt = 0; attempt <= r.retry; attempt++) {
      try {
        final res = await _sendOnce(r);
        last = res;
        if (res.statusCode < 400) return res;
      } on DioException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      }
    }
    if (last != null) return last;
    if (lastError is DioException) {
      final inner = lastError.error;
      throw HttpFailure('${lastError.message ?? inner ?? lastError.type.name} (${r.url})');
    }
    throw HttpFailure('$lastError (${r.url})');
  }

  static Future<HttpResponse> _sendOnce(HttpRequest r) async {
    var method = r.method.toUpperCase();
    var url = r.url;
    var body = r.body;
    final headers = Map<String, String>.from(r.headers);
    final hasUa = headers.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (!hasUa) headers['User-Agent'] = userAgent;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final reqHeaders = Map<String, String>.from(headers);
      if (r.useCookieJar) {
        final stored = CookieStore.getCookie(url);
        if (stored.isNotEmpty) {
          final key = reqHeaders.keys.firstWhere((k) => k.toLowerCase() == 'cookie', orElse: () => '');
          if (key.isEmpty) {
            reqHeaders['Cookie'] = stored;
          } else {
            final merged = CookieStore.cookieToMap(stored)..addAll(CookieStore.cookieToMap(reqHeaders[key]!));
            reqHeaders[key] = CookieStore.mapToCookie(merged) ?? reqHeaders[key]!;
          }
        }
      }
      String? contentType;
      if (body != null && method != 'GET' && method != 'HEAD') {
        final key = reqHeaders.keys.firstWhere((k) => k.toLowerCase() == 'content-type', orElse: () => '');
        if (key.isEmpty) {
          final t = body.trimLeft();
          contentType = t.startsWith('{') || t.startsWith('[') ? 'application/json; charset=UTF-8' : 'application/x-www-form-urlencoded';
        } else {
          contentType = reqHeaders.remove(key);
        }
      }
      final response = await dio.request<List<int>>(
        url,
        data: (method == 'GET' || method == 'HEAD') ? null : body,
        options: Options(
          method: method,
          headers: reqHeaders,
          contentType: contentType,
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (_) => true,
          receiveDataWhenStatusError: true,
          sendTimeout: r.timeout,
          receiveTimeout: r.timeout,
        ),
      );
      final resHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) => resHeaders[name.toLowerCase()] = List<String>.from(values));
      if (r.useCookieJar) {
        final sc = resHeaders['set-cookie'];
        if (sc != null) CookieStore.saveFromResponse(url, sc);
      }
      final code = response.statusCode ?? 0;
      final loc = resHeaders['location']?.firstOrNull;
      if (r.followRedirects && loc != null && (code == 301 || code == 302 || code == 303 || code == 307 || code == 308)) {
        url = Uri.parse(url).resolve(loc).toString();
        if (code == 303 || ((code == 301 || code == 302) && method == 'POST')) {
          method = 'GET';
          body = null;
        }
        continue;
      }
      var bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final enc = resHeaders['content-encoding']?.firstOrNull?.toLowerCase();
      if (enc == 'gzip' || (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)) {
        try {
          bytes = Uint8List.fromList(gzip.decode(bytes));
        } catch (_) {
          // already decompressed by the HTTP client
        }
      } else if (enc == 'deflate') {
        try {
          bytes = Uint8List.fromList(zlib.decode(bytes));
        } catch (_) {}
      }
      return HttpResponse(code, response.statusMessage ?? '', resHeaders, bytes, url);
    }
    throw HttpFailure('too many redirects (${r.url})');
  }

  // charset handling ------------------------------------------------------------------------------------------------------------

  static final RegExp _headerCharset = RegExp(r'charset\s*=\s*"?([\w\-:.]+)', caseSensitive: false);
  static final RegExp _metaCharset = RegExp(r'''<meta[^>]+charset\s*=\s*["']?\s*([\w\-:.]+)''', caseSensitive: false);
  static final RegExp _xmlEncoding = RegExp(r'''^\s*<\?xml[^>]+encoding\s*=\s*["']([\w\-:.]+)["']''', caseSensitive: false);

  /// Legado `ResponseBody.text()`: explicit [charset] > Content-Type charset > BOM > `<meta>`/xml declaration > UTF-8 if valid else GBK.
  static String decodeBody(List<int> bytes, {String? contentType, String? charset}) {
    if (bytes.isEmpty) return '';
    if (charset != null && charset.trim().isNotEmpty) {
      final s = decodeWith(bytes, charset.trim());
      if (s != null) return s;
    }
    if (contentType != null) {
      final m = _headerCharset.firstMatch(contentType);
      if (m != null) {
        final s = decodeWith(bytes, m.group(1)!);
        if (s != null) return s;
      }
    }
    final bom = _bomCharset(bytes);
    if (bom != null) return decodeWith(bytes, bom)!;
    final detected = sniffCharset(bytes);
    if (detected != null) {
      final s = decodeWith(bytes, detected);
      if (s != null) return s;
    }
    final u = _strictUtf8(bytes);
    if (u != null) return u;
    return CjkCharsets.decodeGb18030(bytes);
  }

  static String? _bomCharset(List<int> b) {
    if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) return 'utf-8';
    if (b.length >= 2 && b[0] == 0xff && b[1] == 0xfe) return 'utf-16le';
    if (b.length >= 2 && b[0] == 0xfe && b[1] == 0xff) return 'utf-16be';
    return null;
  }

  /// `<meta charset>` / `<meta http-equiv content="...charset=">` / xml declaration within the first 4 KiB.
  static String? sniffCharset(List<int> bytes) {
    final head = latin1.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes);
    final m = _metaCharset.firstMatch(head) ?? _xmlEncoding.firstMatch(head);
    return m?.group(1);
  }

  static String? _strictUtf8(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Decodes [bytes] with the named charset; null when the name is unknown.
  static String? decodeWith(List<int> bytes, String name) {
    final n = name.trim().toLowerCase().replaceAll('_', '-');
    switch (n) {
      case 'utf-8':
      case 'utf8':
        var b = bytes;
        if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) b = b.sublist(3);
        return const Utf8Decoder(allowMalformed: true).convert(b);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
      case 'gb-2312':
      case 'x-gbk':
      case 'cp936':
      case 'ms936':
        // The original decodes all three with its GBK table (0xe59850); four-byte GB18030 sequences are decoded here too (a GBK
        // page never has a second byte 0x30..0x39, so the four-byte path does not change GBK text).
        return CjkCharsets.decodeGb18030(bytes);
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
      case 'windows-1252':
      case 'ascii':
      case 'us-ascii':
        return latin1.decode(bytes, allowInvalid: true);
      case 'utf-16le':
        return _utf16(bytes, Endian.little);
      case 'utf-16be':
      case 'utf-16':
        return _utf16(bytes, Endian.big);
      case 'big5':
      case 'big5-hkscs':
      case 'x-big5':
      case 'csbig5':
      case 'cp950':
      case 'ms950':
      case 'x-windows-950':
        // not in the original (its switch knows gbk/gb2312/gb18030/latin1/utf-8 only); cp950 table generated from Python's codecs
        return CjkCharsets.decodeBig5(bytes);
    }
    return null;
  }

  static String _utf16(List<int> bytes, Endian e) {
    var start = 0;
    if (bytes.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) start = 2;
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(e == Endian.little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// Encodes [s] for URL/form use in the named charset (`URLEncoder.encode(s, charset)`); UTF-8 when unknown.
  static List<int> encodeWith(String s, String? charset) {
    final n = (charset ?? 'utf-8').trim().toLowerCase();
    switch (n) {
      case 'gbk':
      case 'gb2312':
        return gbk.encode(s);
      case 'gb18030':
        return CjkCharsets.encodeGb18030(s);
      case 'big5':
      case 'big5-hkscs':
      case 'cp950':
        return CjkCharsets.encodeBig5(s);
      case 'iso-8859-1':
      case 'latin1':
        return latin1.encode(s);
    }
    return utf8.encode(s);
  }
}

class HttpFailure implements Exception {
  final String message;
  HttpFailure(this.message);
  @override
  String toString() => 'HttpFailure: $message';
}
