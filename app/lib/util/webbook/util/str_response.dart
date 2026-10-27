// util/webbook/util/str_response.dart - Legado `StrResponse`: the decoded body plus final url / status / headers. It is also the value of
// `java.connect()`, `java.get()`, `java.post()`, `java.head()` in rule JavaScript (`res.body()`, `res.code()`, `res.headers()` ...).
import 'dart:typed_data';

import '../../http.dart';
import '../../legado/js_bindable.dart';

class StrResponse extends JsBindable {
  final String url;
  final int code;
  final String message;
  final Map<String, List<String>> headers;
  String? body;
  final Uint8List? bodyBytes;

  StrResponse(this.url, this.body, {this.code = 200, this.message = '', this.headers = const {}, this.bodyBytes});

  factory StrResponse.fromHttp(HttpResponse r, {String? charset}) => StrResponse(
        r.url,
        AppHttp.decodeBody(r.bodyBytes, contentType: r.contentType, charset: charset),
        code: r.statusCode,
        message: r.statusMessage,
        headers: r.headers,
        bodyBytes: r.bodyBytes,
      );

  bool get isSuccessful => code >= 200 && code < 300;

  String? header(String name) {
    final v = headers[name.toLowerCase()];
    return v == null || v.isEmpty ? null : v.first;
  }

  @override
  String toString() => body ?? '';

  @override
  Iterable<String> get jsMethods => const ['body', 'url', 'code', 'message', 'headers', 'header', 'isSuccessful', 'toString', 'raw'];

  @override
  Object? jsCall(String name, List<Object?> args) {
    switch (name) {
      case 'body':
        return body;
      case 'url':
        return url;
      case 'code':
        return code;
      case 'message':
        return message;
      case 'headers':
        return {for (final e in headers.entries) e.key: e.value.join(', ')};
      case 'header':
        return header('${args.isNotEmpty ? args[0] : ''}');
      case 'isSuccessful':
        return isSuccessful;
      case 'toString':
        return body ?? '';
      case 'raw':
        return this;
    }
    return super.jsCall(name, args);
  }

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'url':
      case 'code':
      case 'message':
        return JsBindable.noMember; // methods in Legado (`res.url()`), so keep them callable
    }
    return JsBindable.noMember;
  }

  /// Plain-data form used by engines that cannot hold native objects (the JS prelude rebuilds the object with methods).
  Map<String, Object?> toPlain() => {
        '__nr': 'StrResponse',
        'url': url,
        'code': code,
        'message': message,
        'headers': {for (final e in headers.entries) e.key: e.value.join(', ')},
        'body': body,
      };
}
