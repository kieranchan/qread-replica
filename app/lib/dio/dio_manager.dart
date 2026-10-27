// dio/dio_manager.dart — the shared Dio instance of the original: `DioManager._instance` (static 0x4b38).
//
// Options recovered from sub_ec604 / closure 0xecb74 / 0xedee8 (Duration values read from the object pool):
//   connectTimeout 15 s, receiveTimeout 60 s, sendTimeout 60 s, persistentConnection on, responseType bytes,
//   validateStatus `status < 500` (a 4xx reply is a normal response, the callers look at the status code);
//   IOHttpClientAdapter with an HttpClient whose connectionTimeout is 15 s, idleTimeout 60 s and whose badCertificateCallback
//   accepts every certificate (book sources are frequently served with self-signed or expired certificates).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class DioManager {
  /// The original accepts any TLS certificate for third-party sites; switch off to validate certificates.
  static bool allowBadCertificates = true;

  static final DioManager _instance = DioManager._();

  factory DioManager() => _instance;

  /// `DioManager._instance` as a getter, like the original's static field.
  static DioManager get instance => _instance;

  late final Dio dio;

  DioManager._() {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      persistentConnection: true,
      responseType: ResponseType.bytes,
      validateStatus: validateStatus,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: createHttpClient);
  }

  /// 0xedee8.
  static bool validateStatus(int? status) {
    if (status == null) throw ArgumentError.notNull('status');
    return status < 500;
  }

  /// 0xecb74.
  static HttpClient createHttpClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60);
    if (allowBadCertificates) c.badCertificateCallback = (cert, host, port) => true;
    return c;
  }
}
