// util/webbook/model/base_source.dart - what book sources and RSS sources share (Legado `BaseSource`): header map (plain JSON or JS),
// `jsLib`, login url/ui/info/header storage, source-level variables, and the `source` object of rule JavaScript.
import 'dart:convert';

import '../../http.dart';
import '../../json.dart';
import '../../legado/js_bindable.dart';
import '../analyze_rule/info_map.dart';
import '../analyze_rule/js_extensions.dart';
import '../util/cache_manager.dart';

abstract class BaseSource extends JsBindable {
  String? get concurrentRate;
  String? get loginUrl;
  String? get loginUi;
  String? get loginCheckJs;
  String? get header;
  bool get enabledCookieJar;
  String? get jsLib;
  String? get variableComment;
  String get sourceComment => '';

  /// The identifying URL (`bookSourceUrl` / `sourceUrl`).
  String getKey();

  String getTag() => getKey();

  // variables -------------------------------------------------------------------------------------------------------------------
  String? getVariable() => CacheManager.getString('sourceVariable_${getKey()}');

  void setVariable(String? variable) {
    if (variable == null || variable.isEmpty) {
      CacheManager.delete('sourceVariable_${getKey()}');
    } else {
      CacheManager.put('sourceVariable_${getKey()}', variable);
    }
  }

  /// `source.get(key)` / `source.put(key, value)`: per-source key/value store (kept by [CacheManager]).
  String get(String key) => CacheManager.getString('v_${getKey()}_$key') ?? '';

  String put(String key, String value) {
    CacheManager.put('v_${getKey()}_$key', value);
    return value;
  }

  // login -----------------------------------------------------------------------------------------------------------------------
  String? getLoginInfo() => CacheManager.getString('userInfo_${getKey()}');

  InfoMap getLoginInfoMap() => InfoMap.fromJsonString(getLoginInfo());

  bool putLoginInfo(String info) {
    CacheManager.put('userInfo_${getKey()}', info);
    return true;
  }

  void removeLoginInfo() => CacheManager.delete('userInfo_${getKey()}');

  String? getLoginHeader() => CacheManager.getString('loginHeader_${getKey()}');

  Map<String, String>? getLoginHeaderMap() {
    final h = getLoginHeader();
    if (h == null || h.isEmpty) return null;
    final m = jsonutil.asMap(h);
    return m?.map((k, v) => MapEntry(k, '$v'));
  }

  void putLoginHeader(String header) {
    CacheManager.put('loginHeader_${getKey()}', header);
  }

  void removeLoginHeader() => CacheManager.delete('loginHeader_${getKey()}');

  // scripts ---------------------------------------------------------------------------------------------------------------------
  /// Runs [js] with `java` bound to this source's JS extensions.
  Future<Object?> evalJS(String js, {Map<String, Object?>? values}) => SourceJsExtensions(this).runJs(js, values: values);

  /// Legado `getHeaderMap`: `header` is JSON, or `@js:`/`<js>` that returns JSON; a User-Agent is always present.
  Future<Map<String, String>> getHeaderMap([bool hasLoginHeader = false]) async {
    final map = <String, String>{};
    final h = header;
    if (h != null && h.trim().isNotEmpty) {
      String text = h.trim();
      final lower = text.toLowerCase();
      if (lower.startsWith('@js:')) {
        text = '${await evalJS(text.substring(4))}';
      } else if (lower.startsWith('<js>')) {
        final end = text.lastIndexOf('<');
        text = '${await evalJS(text.substring(4, end > 4 ? end : text.length))}';
      }
      final m = jsonutil.asMap(text);
      if (m != null) {
        m.forEach((k, v) => map[k] = '$v');
      }
    }
    if (!map.keys.any((k) => k.toLowerCase() == 'user-agent')) map['User-Agent'] = AppHttp.userAgent;
    if (hasLoginHeader) {
      final lh = getLoginHeaderMap();
      if (lh != null) map.addAll(lh);
    }
    return map;
  }

  // JsBindable: the `source` object ------------------------------------------------------------------------------------------------
  @override
  Iterable<String> get jsMethods => const [
        'getKey', 'getTag', 'get', 'put', 'getVariable', 'setVariable', 'getLoginHeader', 'getLoginHeaderMap', 'putLoginHeader',
        'removeLoginHeader', 'getLoginInfo', 'getLoginInfoMap', 'putLoginInfo', 'removeLoginInfo', 'getHeaderMap', 'setVariable',
        'toString',
      ];

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'key':
      case 'bookSourceUrl':
      case 'sourceUrl':
        return getKey();
      case 'loginUrl':
        return loginUrl;
      case 'loginUi':
        return loginUi;
      case 'header':
        return header;
      case 'jsLib':
        return jsLib;
      case 'bookSourceComment':
      case 'sourceComment':
        return sourceComment;
      case 'variableComment':
        return variableComment;
      case 'variable':
        return getVariable();
      case 'concurrentRate':
        return concurrentRate;
      case 'bookSourceName':
      case 'sourceName':
        return sourceName;
    }
    return JsBindable.noMember;
  }

  String get sourceName => getKey();

  @override
  Map<String, Object?> jsSnapshot() => {
        'key': getKey(),
        'bookSourceUrl': getKey(),
        'sourceUrl': getKey(),
        'bookSourceName': sourceName,
        'sourceName': sourceName,
        'loginUrl': loginUrl,
        'loginUi': loginUi,
        'header': header,
        'jsLib': jsLib,
        'bookSourceComment': sourceComment,
        'variableComment': variableComment,
        'variable': getVariable(),
      };

  @override
  Object? jsCall(String name, List<Object?> args) {
    String a(int i) => i < args.length ? '${args[i] ?? ''}' : '';
    switch (name) {
      case 'getKey':
        return getKey();
      case 'getTag':
        return getTag();
      case 'get':
        return get(a(0));
      case 'put':
        return put(a(0), a(1));
      case 'getVariable':
        return getVariable();
      case 'setVariable':
        setVariable(args.isEmpty || args[0] == null ? null : a(0));
        return null;
      case 'getLoginHeader':
        return getLoginHeader();
      case 'getLoginHeaderMap':
        return getLoginHeaderMap();
      case 'putLoginHeader':
        putLoginHeader(a(0));
        return null;
      case 'removeLoginHeader':
        removeLoginHeader();
        return null;
      case 'getLoginInfo':
        return getLoginInfo();
      case 'getLoginInfoMap':
        return getLoginInfoMap().map;
      case 'putLoginInfo':
        return putLoginInfo(a(0));
      case 'removeLoginInfo':
        removeLoginInfo();
        return null;
      case 'getHeaderMap':
        return jsAwait('source.getHeaderMap:${getKey()}:${a(0)}', () => getHeaderMap(a(0) == 'true'));
      case 'toString':
        return jsonEncode({'key': getKey()});
    }
    return super.jsCall(name, args);
  }
}
