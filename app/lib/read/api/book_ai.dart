// read/api/book_ai.dart — per-chapter result of the AI purification (`<documents>/bookai`).
//
// Original: class 1513 `AiContext` = {oldtext, text} (JSON 0x2a5290 / 0x2a61fc) and class 1516 `BookAi` with the isolate pair
// `_saveToLocalIsolate(_SaveRulesParams)` 0x2a6460 / `_readFromLocalIsolate(_ReadRulesParams)` 0x2a61cc. `oldtext` is the chapter text
// the AI was given, `text` what it returned. The AI call itself lives in `ai/` (extras area); this class only keeps the result.
import '../../models/_json.dart';
import 'chapter_json_store.dart';
import 'read_storage_root.dart';

class AiContext {
  String oldtext;
  String text;

  AiContext({this.oldtext = '', this.text = ''});

  factory AiContext.fromJson(Map<String, dynamic> json) => AiContext(oldtext: jStr(json['oldtext']), text: jStr(json['text']));

  Map<String, dynamic> toJson() => {'oldtext': oldtext, 'text': text};
}

class BookAi {
  final ChapterJsonStore _store;

  BookAi({ChapterJsonStore? store}) : _store = store ?? ChapterJsonStore(ReadStorageRoot.bookai);

  Future<AiContext?> readFromLocal(String bookUrl, int index) async {
    final m = await _store.read(bookUrl, index);
    return m == null ? null : AiContext.fromJson(m);
  }

  Future<void> saveToLocal(String bookUrl, int index, AiContext ctx) => _store.save(bookUrl, index, ctx.toJson());

  Future<void> deleteBook(String bookUrl) => _store.deleteBook(bookUrl);
}
