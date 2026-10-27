// qread/http.dart — POST helper for the account/cloud API (the original runs `_performPostRequest` in an isolate through
// Dio and decodes the reply with `_decodeBytes`; here a plain Dio call).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class QHttpException implements Exception {
  final String message;
  const QHttpException(this.message);
  @override
  String toString() => message;
}

abstract class QHttp {
  /// Replaceable in tests.
  static Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  ));

  static Map<String, dynamic> _decode(Response<dynamic> r) {
    final data = r.data;
    final bytes = data is Uint8List ? data : Uint8List.fromList(List<int>.from(data as List));
    final text = utf8.decode(bytes, allowMalformed: true);
    try {
      final j = jsonDecode(text);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    throw QHttpException('服务器返回格式错误 (${r.statusCode})');
  }

  /// JSON body, JSON reply. The map keeps the `{code, data, errorMsg}` shape of the API.
  static Future<Map<String, dynamic>> post(String url, Map<String, dynamic> body, {Duration? timeout}) async {
    try {
      final r = await dio.post<dynamic>(
        url,
        data: body,
        options: Options(contentType: Headers.jsonContentType, receiveTimeout: timeout, sendTimeout: timeout),
      );
      return _decode(r);
    } on DioException catch (e) {
      throw QHttpException('网络错误: ${e.message ?? e.type.name}');
    }
  }

  /// GET returning JSON (health check).
  static Future<Map<String, dynamic>> get(String url) async {
    try {
      return _decode(await dio.get<dynamic>(url, options: Options(receiveTimeout: const Duration(seconds: 10))));
    } on DioException catch (e) {
      throw QHttpException('网络错误: ${e.message ?? e.type.name}');
    }
  }

  /// multipart/form-data with one file part named [field]; [query] carries token and parameters (as `setItemJsonFile?tockenid=…`).
  static Future<Map<String, dynamic>> postFile(
    String url,
    Map<String, String> query,
    List<int> bytes,
    String filename, {
    String field = 'file',
  }) async {
    try {
      final form = FormData.fromMap({field: MultipartFile.fromBytes(bytes, filename: filename)});
      final r = await dio.post<dynamic>(url, queryParameters: query, data: form);
      return _decode(r);
    } on DioException catch (e) {
      throw QHttpException('网络错误: ${e.message ?? e.type.name}');
    }
  }
}
