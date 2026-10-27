// util/webbook/util/cache_manager.dart - the `cache.*` store of the JS bridge (cache.get/put/getFromMemory/putMemory/delete ...).
// Values live in memory; the data layer can mirror them to disk through [onSave]/[onDelete] and pre-fill with [load].
import '../../legado/js_bindable.dart';
import '../model/cache.dart';

abstract class CacheManager {
  static final Map<String, Cache> _store = {};
  static final Map<String, Object?> _memory = {};

  /// Persistence hooks (set by the app); called after every put/delete of the durable store.
  static void Function(Cache)? onSave;
  static void Function(String key)? onDelete;

  static void load(Iterable<Cache> items) {
    for (final c in items) {
      _store[c.key] = c;
    }
  }

  static void put(String key, Object? value, {int saveTimeSeconds = 0}) {
    final deadline = saveTimeSeconds == 0 ? 0 : DateTime.now().millisecondsSinceEpoch + saveTimeSeconds * 1000;
    final c = Cache(key: key, value: value, deadline: deadline);
    _store[key] = c;
    onSave?.call(c);
  }

  static Object? get(String key) {
    final c = _store[key];
    if (c == null) return null;
    if (c.isExpired) {
      delete(key);
      return null;
    }
    return c.value;
  }

  static String? getString(String key) {
    final v = get(key);
    return v?.toString();
  }

  static int? getInt(String key) {
    final v = get(key);
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  static double? getDouble(String key) {
    final v = get(key);
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}');
  }

  static void delete(String key) {
    _store.remove(key);
    onDelete?.call(key);
  }

  static void putMemory(String key, Object? value) => _memory[key] = value;
  static Object? getFromMemory(String key) => _memory[key];
  static void deleteMemory(String key) => _memory.remove(key);

  static void clear() {
    for (final k in _store.keys.toList()) {
      delete(k);
    }
    _memory.clear();
  }

  /// Test helper: forget everything without calling the persistence hooks.
  static void resetForTests() {
    _store.clear();
    _memory.clear();
    onSave = null;
    onDelete = null;
  }
}

/// JavaScript `cache` object.
class CacheBinding extends JsBindable {
  static final CacheBinding instance = CacheBinding();

  @override
  Iterable<String> get jsMethods => const [
        'get', 'put', 'putFile', 'getFile', 'getFromMemory', 'putMemory', 'deleteMemory', 'delete', 'getInt', 'getLong',
        'getDouble', 'getFloat', 'getByteArray', 'clear', 'allget', 'allset', 'allremove', 'set', 'remove',
      ];

  @override
  Object? jsCall(String name, List<Object?> args) {
    String k(int i) => i < args.length ? '${args[i] ?? ''}' : '';
    switch (name) {
      case 'get':
      case 'getFile':
        return CacheManager.get(k(0));
      case 'put':
      case 'putFile':
      case 'set':
        final v = args.length > 1 ? args[1] : null;
        final t = args.length > 2 && args[2] is num ? (args[2] as num).toInt() : 0;
        CacheManager.put(k(0), v is JsBindable ? v.toString() : v, saveTimeSeconds: t);
        return v;
      case 'getFromMemory':
        return CacheManager.getFromMemory(k(0));
      case 'putMemory':
        CacheManager.putMemory(k(0), args.length > 1 ? args[1] : null);
        return args.length > 1 ? args[1] : null;
      case 'deleteMemory':
        CacheManager.deleteMemory(k(0));
        return null;
      case 'delete':
      case 'remove':
        CacheManager.delete(k(0));
        return null;
      case 'getInt':
      case 'getLong':
        return CacheManager.getInt(k(0));
      case 'getDouble':
      case 'getFloat':
        return CacheManager.getDouble(k(0));
      case 'getByteArray':
        final v = CacheManager.get(k(0));
        return v is List ? v : null;
      case 'clear':
        CacheManager.clear();
        return null;
    }
    return super.jsCall(name, args);
  }
}
