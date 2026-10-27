// read/api/book_hight.dart — per-chapter result of the highlight rules (original spelling `BookHight`; `<documents>/high`).
//
// Original: class 1505 `HContext` = {oldtext, text, md5} (JSON 0x2a67ac / 0x2a6e28) and class 1508 `BookHight` with the isolate pair
// `_saveToLocalIsolate(_SaveRulesParams)` 0x2a677c / `_readFromLocalIsolate(_ReadRulesParams)` 0x2a6df8. `oldtext` is the text before
// highlighting, `text` the marked-up result, `md5` the fingerprint of the highlight rule list that produced it.
import '../../models/_json.dart';
import 'chapter_json_store.dart';
import 'read_storage_root.dart';

class HContext {
  String oldtext;
  String text;
  String md5;

  HContext({this.oldtext = '', this.text = '', this.md5 = ''});

  factory HContext.fromJson(Map<String, dynamic> json) => HContext(
        oldtext: jStr(json['oldtext']),
        text: jStr(json['text']),
        md5: jStr(json['md5']),
      );

  Map<String, dynamic> toJson() => {'oldtext': oldtext, 'text': text, 'md5': md5};
}

class BookHight {
  final ChapterJsonStore _store;

  BookHight({ChapterJsonStore? store}) : _store = store ?? ChapterJsonStore(ReadStorageRoot.high);

  Future<HContext?> readFromLocal(String bookUrl, int index) async {
    final m = await _store.read(bookUrl, index);
    return m == null ? null : HContext.fromJson(m);
  }

  Future<void> saveToLocal(String bookUrl, int index, HContext ctx) => _store.save(bookUrl, index, ctx.toJson());

  Future<void> deleteBook(String bookUrl) => _store.deleteBook(bookUrl);
}
