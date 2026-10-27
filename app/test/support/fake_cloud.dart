// An in-memory stand-in for the owner's cloud-sync endpoints, shared by the sync tests.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:newread/api/userapi.dart' show CloudKind;
import 'package:newread/data/cloud_api.dart';

String md5Of(String s) => crypto.md5.convert(utf8.encode(s)).toString();
/// In-memory stand-in for the owner's server (docs/API.md "Cloud sync"): etag = md5 of the stored list,
/// update-url answers like the original expects: the server etag when the client's etag is current, `''` when newer data exists
/// or nothing is stored, `'-1'` on failure.
class FakeCloud implements CloudApi {
  final Map<CloudKind, String> lists = {};
  final Map<String, String> items = {};
  int uploads = 0;
  int listCalls = 0;
  int updateCalls = 0;
  bool failUpdate = false;

  static const _itemKind = {
    'books': CloudKind.books,
    'rss': CloudKind.rss,
    'sources': CloudKind.sources,
    'notes': CloudKind.notes,
    'groups': CloudKind.groups,
  };

  String _etag(CloudKind k) => lists[k] == null ? '' : md5Of(lists[k]!);

  @override
  Future<String> etag(CloudKind kind) async => _etag(kind);

  @override
  Future<String> updateUrl(CloudKind kind, String etag) async {
    updateCalls++;
    if (failUpdate) return '-1';
    final e = _etag(kind);
    if (e.isEmpty) return '';
    return etag == e ? e : '';
  }

  @override
  Future<String> list(CloudKind kind) async {
    listCalls++;
    return lists[kind] ?? '';
  }

  @override
  Future<String> getItemJson(String item) async => items[item] ?? '';

  @override
  Future<String> getItemMd5(String item) async => items[item] == null ? '' : md5Of(items[item]!);

  @override
  Future<void> setItemJsonFile(String item, String content) async {
    uploads++;
    final kind = _itemKind[item];
    if (kind != null) {
      lists[kind] = content;
    } else {
      items[item] = content;
    }
  }

  List<Map<String, dynamic>> books() => [for (final e in jsonDecode(lists[CloudKind.books] ?? '[]') as List) Map<String, dynamic>.from(e as Map)];
}
