// data/list_store.dart — the persistence pattern every data manager of the original repeats (not a file of the original):
//
//   XData.load()  read the file-store key, `""` -> defaults, JSON decode, `fromJson` each element, empty -> defaults,
//                 add md5(key) to `Common.cleanwhite` (so "clean items" keeps it)
//   XData.save()  `Storage.write(key, jsonEncode(list))`; a failure is logged (`debugPrint('<x>保存失败 $e')`) and not thrown
//   X.op()        `_lock.synchronized(() async { ...mutate the static list...; await save(); })`
//
// [ListStore] holds the static list, the lock and these two steps, so each manager only adds its domain operations.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../common/lock.dart';
import '../storage/storage.dart';

class ListStore<T> {
  /// File-store key (e.g. `replaces`).
  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  /// Built-in list used when nothing (or an empty list) is stored; each call must build fresh objects.
  final List<T> Function()? defaults;

  /// Prefix of the log line printed when saving fails, e.g. `替换规则`.
  final String label;

  final Lock lock = Lock();
  List<T> items = <T>[];
  bool loaded = false;

  /// Called after every successful [save] (the original schedules the device backup of sources / RSS from its save functions).
  void Function()? onSaved;

  ListStore(this.key, {required this.fromJson, required this.toJson, this.defaults, this.label = ''});

  /// Forgets the in-memory list so the next [load] reads from disk again (tests, logout).
  void reset() {
    items = <T>[];
    loaded = false;
  }

  /// Reads the stored list. Safe to call again with [force] to reload from disk.
  Future<List<T>> load({bool force = false}) async {
    if (loaded && !force) return items;
    Storage.keepOnClean(key);
    var list = <T>[];
    try {
      final text = await Storage.read(key);
      if (text.isNotEmpty) {
        final v = jsonDecode(text);
        if (v is List) {
          for (final e in v) {
            if (e is Map) {
              try {
                list.add(fromJson(Map<String, dynamic>.from(e)));
              } catch (err) {
                debugPrint('$label解析失败 $err');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('$label读取失败 $e');
    }
    if (list.isEmpty && defaults != null) list = defaults!();
    items = list;
    loaded = true;
    return items;
  }

  /// Writes the list; returns false (after logging) when the write failed.
  Future<bool> save() async {
    try {
      await Storage.write(key, jsonEncode([for (final e in items) toJson(e)]));
      onSaved?.call();
      return true;
    } catch (e) {
      debugPrint('$label保存失败 $e');
      return false;
    }
  }

  /// Runs [body] under the lock with the loaded list; saves afterwards unless [persist] is false.
  Future<R> run<R>(FutureOr<R> Function(List<T> items) body, {bool persist = true}) {
    return lock.synchronized(() async {
      await load();
      final r = await body(items);
      if (persist) await save();
      return r;
    });
  }
}

/// A new unique id for a rule/template/server (the original takes it from `package:uuid` under `_uuidlock`).
String newId() => const Uuid().v4();
