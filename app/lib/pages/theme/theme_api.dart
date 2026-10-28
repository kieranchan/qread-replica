// pages/theme/theme_api.dart — client of the theme plaza (docs/API.md §3), read from the list call 0x1099b00, categories 0x10e1120,
// detail 0x1040c64 and the item parsers 0x81b908 / 0x6cfab8 / 0x6cfff0.
//
//   GET {base}public/themes?page&limit&category_id → {code:200, data:{items, total, page, limit, max_page}}
//   GET {base}public/categories                     → {code, data:[{id,name}]}
//   GET {base}public/themes/<id>                    → {code, data:item}
//   files: {base} + <zip_path | layout_path | image_path> (paths start with `public/files/…` or `/public/files/…`)
// Success is `code < 400`; failures carry `message` (`Failed to get themes: <message>`). The original host is
// `http://theme2.qread.xyz`; the replica uses the owner's server (`Common.apiBase`).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../common/common.dart';

class ThemeCategory {
  final int id;
  final String name;
  const ThemeCategory(this.id, this.name);

  factory ThemeCategory.fromJson(Map<String, dynamic> j) => ThemeCategory(_int(j['id']), '${j['name'] ?? ''}');
}

/// One theme of the plaza (0x81b908).
class PlazaTheme {
  final int id;
  final String name;
  final String description;
  final int categoryId;
  final ThemeCategory? category;
  final String zipPath;
  final String layoutPath;
  final String imagePath;
  final String version;
  final String author;

  /// `theme_mode`: `day` = a day theme, anything else a night theme (the plaza card / detail 0x6cb994: `day` → `☀ 白天`, otherwise
  /// `🌙 夜间`; the app itself sends `day` / `dark` by the current brightness, 0x5ac588).
  final String themeMode;
  final String createdAt;
  final String updatedAt;

  const PlazaTheme({
    required this.id,
    this.name = '',
    this.description = '',
    this.categoryId = 0,
    this.category,
    this.zipPath = '',
    this.layoutPath = '',
    this.imagePath = '',
    this.version = '',
    this.author = '',
    this.themeMode = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  bool get isNight => themeMode != 'day';

  factory PlazaTheme.fromJson(Map<String, dynamic> j) => PlazaTheme(
        id: _int(j['id']),
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        categoryId: _int(j['category_id']),
        category: j['category'] is Map ? ThemeCategory.fromJson(Map<String, dynamic>.from(j['category'] as Map)) : null,
        zipPath: '${j['zip_path'] ?? ''}',
        layoutPath: '${j['layout_path'] ?? ''}',
        imagePath: '${j['image_path'] ?? ''}',
        version: '${j['version'] ?? ''}',
        author: '${j['author'] ?? ''}',
        themeMode: '${j['theme_mode'] ?? ''}',
        createdAt: '${j['created_at'] ?? ''}',
        updatedAt: '${j['updated_at'] ?? ''}',
      );
}

class PlazaPage {
  final List<PlazaTheme> items;
  final int total;
  final int page;
  final int limit;
  final int maxPage;
  const PlazaPage(this.items, {this.total = 0, this.page = 1, this.limit = 20, this.maxPage = 1});

  bool get hasMore => page < maxPage;
}

class ThemeApiException implements Exception {
  final String message;
  const ThemeApiException(this.message);
  @override
  String toString() => message;
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

class ThemePlazaApi {
  /// Base url with trailing slash; defaults to the account server.
  final String base;
  final Dio dio;

  ThemePlazaApi({String? base, Dio? dio})
      : base = _slash(base ?? Common.apiBase),
        dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  static String _slash(String s) => s.endsWith('/') ? s : '$s/';

  /// Absolute url of a stored file path (`public/files/...`), or the path itself when it is already absolute.
  String fileUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$base${path.startsWith('/') ? path.substring(1) : path}';
  }

  Future<Map<String, dynamic>> _get(String path, String what, {Map<String, dynamic>? query}) async {
    Response<dynamic> r;
    try {
      r = await dio.get<dynamic>('$base$path', queryParameters: query, options: Options(responseType: ResponseType.plain, validateStatus: (_) => true));
    } on DioException catch (e) {
      throw ThemeApiException('$what${e.message ?? e.type.name}');
    }
    Map<String, dynamic> j;
    try {
      final v = r.data is String ? jsonDecode(r.data as String) : r.data;
      j = Map<String, dynamic>.from(v as Map);
    } catch (_) {
      throw ThemeApiException('$what${r.statusCode}');
    }
    final code = _int(j['code'] ?? r.statusCode);
    if (code >= 400) throw ThemeApiException('$what${j['message'] ?? code}');
    return j;
  }

  /// 0x1099b00. [categoryId] 0 = 全部.
  Future<PlazaPage> themes({int page = 1, int limit = 20, int categoryId = 0}) async {
    final j = await _get('public/themes', 'Failed to get themes: ', query: {
      'page': page,
      'limit': limit,
      if (categoryId > 0) 'category_id': categoryId,
    });
    final d = j['data'];
    if (d is! Map) return const PlazaPage([]);
    final items = [for (final e in (d['items'] as List? ?? const [])) if (e is Map) PlazaTheme.fromJson(Map<String, dynamic>.from(e))];
    return PlazaPage(items,
        total: _int(d['total']), page: _int(d['page'] ?? page), limit: _int(d['limit'] ?? limit), maxPage: _int(d['max_page'] ?? 1));
  }

  /// 0x10e1120.
  Future<List<ThemeCategory>> categories() async {
    final j = await _get('public/categories', 'Failed to get categories: ');
    final d = j['data'];
    if (d is! List) return [];
    return [for (final e in d) if (e is Map) ThemeCategory.fromJson(Map<String, dynamic>.from(e))];
  }

  /// 0x1040c64.
  Future<PlazaTheme> theme(int id) async {
    final j = await _get('public/themes/$id', 'Failed to get themes: ');
    final d = j['data'];
    if (d is! Map) throw const ThemeApiException('主题不存在');
    return PlazaTheme.fromJson(Map<String, dynamic>.from(d));
  }

  /// Downloads a file of the plaza; [onProgress] gets 0..1.
  Future<Uint8List> download(String path, {void Function(double)? onProgress, CancelToken? cancelToken}) async {
    try {
      final r = await dio.get<List<int>>(
        fileUrl(path),
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
        onReceiveProgress: (n, total) {
          if (total > 0 && onProgress != null) onProgress(n / total);
        },
      );
      return Uint8List.fromList(r.data ?? const []);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ThemeApiException('下载失败: ${e.message ?? e.type.name}');
    }
  }
}
