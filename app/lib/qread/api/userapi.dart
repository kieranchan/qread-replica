// qread/api/userapi.dart — bookshelf call of the bound 轻阅读 backend (`UserApi` in `package:newread/qread/api/userapi.dart`;
// not to be confused with the account API `api/userapi.dart`). Original: `/getBookshelfNew` 0xfa8f6c (`md5`, `page`).
import '../qread.dart';

abstract class UserApi {
  /// One page of the backend bookshelf as raw book maps (the shelf area converts them).
  static Future<List<Map<String, dynamic>>> bookshelf({int page = 1, String md5 = ''}) async {
    final data = await Qread.post('/getBookshelfNew', {'md5': md5, 'page': page});
    final list = data is Map ? (data['list'] ?? data['data']) : data;
    return [for (final e in (list is List ? list : const [])) if (e is Map) Map<String, dynamic>.from(e)];
  }
}
