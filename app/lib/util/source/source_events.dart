// util/source/source_events.dart — not a file of the original: the app side of a 时光源's `callbackjs(event, book)` (书源编辑 →
// 事件监听, 0xe08528 -> 0xe085bc) and of its 定制按钮. The original sends (book = the book's JSON text):
//   * detail page (only with 事件监听 on; a loading veil while the page answers): clickBookName, longClickBookName (not consumed ->
//     search the name), clickAuthor, longClickAuthor (not consumed -> search the author), clickBookLabel / longClickBookLabel
//     (the kind tags) — 0xfb7b78 / 0xfb797c / 0xfb7888 / 0xfb7668 / 0xfb7574 / 0xfb7488;
//   * 定制按钮 (customButton on): a round button in the detail page's app bar (clickCustomButton, 0xfb49e8) and in the reader's top
//     bar (tap clickCustomButton, long press longClickCustomButton, 0x10e950c / 0x10e93c4), sent whether 事件监听 is on or not;
//   * not consumable, fire and forget (事件监听 on): addBookShelf (0xf99388, before the add dialog), delBookShelf (0xf700b4,
//     after the delete confirmation), saveRead (0xe078d4, every saved reading progress).
// A page answering `true` consumes the event: the app's own action is skipped. Sources of the bound 轻阅读 backend never get events.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/source.dart';
import '../../models/book.dart';
import 'run.dart';
import 'source.dart';

abstract class SourceEvents {
  static const String clickBookName = 'clickBookName';
  static const String longClickBookName = 'longClickBookName';
  static const String clickAuthor = 'clickAuthor';
  static const String longClickAuthor = 'longClickAuthor';
  static const String clickCustomButton = 'clickCustomButton';
  static const String longClickCustomButton = 'longClickCustomButton';
  static const String clickBookLabel = 'clickBookLabel';
  static const String longClickBookLabel = 'longClickBookLabel';
  static const String addBookShelf = 'addBookShelf';
  static const String delBookShelf = 'delBookShelf';
  static const String saveRead = 'saveRead';

  static bool _on(Object? v) => v == true || '$v' == 'true' || '$v' == '1';

  /// The stored 时光源 of [origin] (null for other sources and for sources of the bound backend).
  static Map<String, dynamic>? _source(String origin) {
    if (origin.isEmpty) return null;
    final raw = Sourcedata.byUrl(origin);
    if (raw == null || _on(raw['isqread']) || !BaseSource.isTimeSource(raw)) return null;
    return raw;
  }

  /// 事件监听 is on for the source of [origin].
  static bool listens(String origin) => _on(_source(origin)?['eventListener']);

  /// 定制按钮 is on for the source of [origin].
  static bool hasCustomButton(String origin) => _on(_source(origin)?['customButton']);

  /// Sends [event] with [book] to the page of [origin] (no 事件监听 check: the custom buttons); true = consumed.
  static Future<bool> send(String origin, String event, Book book) async {
    final raw = _source(origin);
    if (raw == null) return false;
    try {
      final run = await SourceRun.of(BaseSource.fromJson(raw));
      return await run.callbackjs(event, jsonEncode(book.toJson()));
    } catch (e) {
      debugPrint('callbackjs $event: $e');
      return false;
    }
  }

  /// Sends [event] when the source of [book] listens; false when it does not or the page did not consume it.
  static Future<bool> notify(String event, Book book) async {
    if (!listens(book.origin)) return false;
    return send(book.origin, event, book);
  }

  /// The not consumable events (addBookShelf / delBookShelf / saveRead): sent without waiting.
  static void fire(String event, Book book) {
    if (listens(book.origin)) unawaited(send(book.origin, event, book));
  }
}
