// dio/tts_dio_manger.dart — the Dio instance used for TTS vendor requests: `TtsDioManger._instance` (static 0x3f90).
// Same shape as `DioManager` but a shorter connect timeout (sub_2005b4 / closure 0x2006e4): connectTimeout 10 s,
// receiveTimeout 60 s, sendTimeout 60 s, responseType bytes, validateStatus `status < 500`; its HttpClient has
// connectionTimeout 10 s, idleTimeout 60 s and accepts every certificate.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'dio_manager.dart';

class TtsDioManger {
  static final TtsDioManger _instance = TtsDioManger._();

  factory TtsDioManger() => _instance;

  static TtsDioManger get instance => _instance;

  late final Dio dio;

  TtsDioManger._() {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      persistentConnection: true,
      responseType: ResponseType.bytes,
      validateStatus: DioManager.validateStatus,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: createHttpClient);
  }

  /// 0x2006e4.
  static HttpClient createHttpClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 60);
    if (DioManager.allowBadCertificates) c.badCertificateCallback = (cert, host, port) => true;
    return c;
  }
}
