// read/api/book_rules.dart — per-chapter result of the replace / purify rules (`<documents>/bookrule`).
//
// Original (class 1498 `RuleContext` = {md5, text, rules}, JSON by 0x2a6374 / 0x2a64c0; class 1499 `BookRules` with the isolate pair
// `_saveToLocalIsolate(_SaveRulesParams)` 0x2a6344 / `_readFromLocalIsolate(_ReadRulesParams)` 0x2a6490). `md5` is the digest of the
// chapter text the rules were applied to, `text` the result, `rules` the rules that produced it (so that a changed rule list or a changed
// chapter invalidates the entry).
import 'dart:convert';


import '../../models/_json.dart';
import '../../models/replacerule.dart';
import 'chapter_json_store.dart';
import 'read_file_store.dart';
import 'read_storage_root.dart';

class RuleContext {
  String md5;
  String text;
  List<ReplaceRule> rules;

  RuleContext({this.md5 = '', this.text = '', List<ReplaceRule>? rules}) : rules = rules ?? <ReplaceRule>[];

  factory RuleContext.fromJson(Map<String, dynamic> json) => RuleContext(
        md5: jStr(json['md5']),
        text: jStr(json['text']),
        rules: jList(json['rules']).map((e) => ReplaceRule.fromJson(jMap(e))).toList(),
      );

  Map<String, dynamic> toJson() => {
        'md5': md5,
        'text': text,
        'rules': rules.map((r) => r.toJson()).toList(),
      };

  /// Digest of a chapter text, the key of [md5].
  static String digestOf(String text) => ReadFileStore.md5Hex(text);

  /// Fingerprint of a rule list (order matters): the cache is only valid for the same rules.
  static String rulesSignature(List<ReplaceRule> rules) => ReadFileStore.md5Hex(jsonEncode(rules.map((r) => r.toJson()).toList()));
}


class BookRules {
  final ChapterJsonStore _store;

  BookRules({ChapterJsonStore? store}) : _store = store ?? ChapterJsonStore(ReadStorageRoot.bookrule);

  Future<RuleContext?> readFromLocal(String bookUrl, int index) async {
    final m = await _store.read(bookUrl, index);
    return m == null ? null : RuleContext.fromJson(m);
  }

  Future<void> saveToLocal(String bookUrl, int index, RuleContext ctx) => _store.save(bookUrl, index, ctx.toJson());

  Future<void> deleteBook(String bookUrl) => _store.deleteBook(bookUrl);
}
