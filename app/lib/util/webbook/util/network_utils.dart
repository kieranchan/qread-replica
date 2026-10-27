// util/webbook/util/network_utils.dart - Legado `NetworkUtils` (absolute URLs, base url, sub-domain, URL-encoding checks).
import 'dart:convert';

class NetworkUtils {
  /// `url,{json}` separator used by AnalyzeUrl and by `getAbsoluteURL` when the base is such a rule.
  static final RegExp paramPattern = RegExp(r'\s*,\s*(?=\{)');

  static final RegExp _absUrl = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

  static bool isAbsUrl(String s) => _absUrl.hasMatch(s);
  static bool isDataUrl(String s) => s.startsWith('data:');
  static bool isJsonType(String s) {
    final t = s.trimLeft();
    return (t.startsWith('{') && s.trimRight().endsWith('}')) || (t.startsWith('[') && s.trimRight().endsWith(']'));
  }

  static bool isXmlType(String s) {
    final t = s.trim();
    return t.startsWith('<') && t.endsWith('>');
  }

  static bool isUrl(String s) => RegExp(r'^https?://[^\s]+$', caseSensitive: false).hasMatch(s.trim());

  /// Legado `getAbsoluteURL(baseURL, relativePath)`. [baseUrl] may be a url rule (`url,{...}`).
  static String getAbsoluteURL(String? baseUrl, String relativePath) {
    final rel = relativePath.trim();
    if (baseUrl == null || baseUrl.isEmpty) return rel;
    if (rel.isEmpty) return baseUrl.split(paramPattern).first;
    if (isAbsUrl(rel) || isDataUrl(rel)) return rel;
    if (rel.startsWith('javascript')) return '';
    final base = baseUrl.split(paramPattern).first.trim();
    try {
      final b = Uri.parse(base);
      if (!b.hasScheme) return rel;
      return b.resolve(rel).toString();
    } on FormatException {
      return rel;
    }
  }

  static String getAbsoluteUri(Uri? base, String relativePath) => getAbsoluteURL(base?.toString(), relativePath);

  /// `scheme://host[:port]` of [url] or null when it is not an absolute URL.
  static String? getBaseUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.split(paramPattern).first;
    final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#]+)').firstMatch(u.trim());
    return m?.group(1);
  }

  static String? getDomain(String url) {
    final b = getBaseUrl(url);
    if (b == null) return null;
    final i = b.indexOf('://');
    var host = b.substring(i + 3);
    final at = host.lastIndexOf('@');
    if (at >= 0) host = host.substring(at + 1);
    final colon = host.lastIndexOf(':');
    if (colon > 0 && !host.endsWith(']')) host = host.substring(0, colon);
    return host;
  }

  static final RegExp _ip = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// Legado `getSubDomain`: the registrable-looking domain used as cookie key (`m.a.example.com` -> `example.com`).
  static String getSubDomain(String url) {
    final host = getDomain(url);
    if (host == null) return url;
    if (_ip.hasMatch(host) || host == 'localhost' || host.startsWith('[')) return host;
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    const sld = {'com', 'net', 'org', 'gov', 'edu', 'co', 'ac'};
    final last = labels.last;
    final second = labels[labels.length - 2];
    if (last.length == 2 && sld.contains(second) && labels.length >= 3) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return labels.sublist(labels.length - 2).join('.');
  }

  /// True when [s] already holds percent-escapes (`%E4%BD`), i.e. must not be encoded again.
  static bool hasUrlEncoded(String s) {
    var i = 0;
    var found = false;
    while (i < s.length) {
      final c = s[i];
      if (c == '%') {
        if (i + 2 >= s.length) return false;
        if (!RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(s.substring(i + 1, i + 3))) return false;
        found = true;
        i += 3;
        continue;
      }
      final code = c.codeUnitAt(0);
      final ok = (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5a) ||
          (code >= 0x61 && code <= 0x7a) ||
          '*-_.+=&'.contains(c);
      if (!ok) return false;
      i++;
    }
    return found;
  }

  /// `java.net.URLEncoder.encode(s, "UTF-8")`: space becomes '+', unreserved `*-_.` stay.
  static String urlEncodeUtf8(String s) => encodeBytes(utf8.encode(s));

  static String encodeBytes(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      final ok = (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5a) ||
          (b >= 0x61 && b <= 0x7a) ||
          b == 0x2a ||
          b == 0x2d ||
          b == 0x5f ||
          b == 0x2e;
      if (ok) {
        sb.writeCharCode(b);
      } else if (b == 0x20) {
        sb.write('+');
      } else {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }

  /// `URLDecoder.decode` (UTF-8): '+' is a space.
  static String urlDecode(String s, [String charset = 'UTF-8']) {
    final bytes = <int>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '+') {
        bytes.add(0x20);
        i++;
      } else if (c == '%' && i + 2 < s.length) {
        final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v == null) {
          bytes.addAll(utf8.encode(c));
          i++;
        } else {
          bytes.add(v);
          i += 3;
        }
      } else {
        bytes.addAll(utf8.encode(c));
        i++;
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
