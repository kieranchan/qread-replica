// util/legado/http_client.dart - small convenience client over [AppHttp] returning [StrResponse]s (the original's `http_client.dart` reads
// `charset=` from the Content-Type and works on `bodyBytes`; that is AppHttp.decodeBody here).
import '../http.dart';
import '../webbook/util/str_response.dart';

class LegadoHttpClient {
  final Map<String, String> defaultHeaders;
  final Duration timeout;

  LegadoHttpClient({this.defaultHeaders = const {}, this.timeout = const Duration(seconds: 30)});

  Future<StrResponse> get(String url, {Map<String, String>? headers, String? charset, int retry = 0}) =>
      _send('GET', url, headers, null, charset, retry);

  Future<StrResponse> post(String url, {String? body, Map<String, String>? headers, String? charset, int retry = 0}) =>
      _send('POST', url, headers, body, charset, retry);

  Future<StrResponse> head(String url, {Map<String, String>? headers}) => _send('HEAD', url, headers, null, null, 0);

  Future<StrResponse> _send(String method, String url, Map<String, String>? headers, String? body, String? charset, int retry) async {
    final res = await AppHttp.send(HttpRequest(
      url: url,
      method: method,
      headers: {...defaultHeaders, ...?headers},
      body: body,
      timeout: timeout,
      retry: retry,
    ));
    return StrResponse.fromHttp(res, charset: charset);
  }
}
