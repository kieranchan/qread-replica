// util/html/entities.dart - HTML entity decode/encode (the original's `_htmlEntityRe` table: amp lt gt quot nbsp #x.. #X.. plus the usual
// named entities of jsoup's `Entities.unescape`).

const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ensp': ' ',
  'emsp': ' ',
  'thinsp': ' ',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'sbquo': '‚',
  'bdquo': '„',
  'bull': '•',
  'middot': '·',
  'laquo': '«',
  'raquo': '»',
  'yen': '¥',
  'euro': '€',
  'pound': '£',
  'cent': '¢',
  'sect': '§',
  'times': '×',
  'divide': '÷',
  'deg': '°',
  'plusmn': '±',
  'frac12': '½',
  'frac14': '¼',
  'frac34': '¾',
  'larr': '←',
  'rarr': '→',
  'uarr': '↑',
  'darr': '↓',
  'hearts': '♥',
  'iexcl': '¡',
  'iquest': '¿',
  'para': '¶',
  'sup2': '²',
  'sup3': '³',
};

final RegExp _entityRe = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);?');

/// jsoup `Entities.unescape`: decodes `&amp;`-style and numeric entities, leaves unknown ones untouched.
String htmlDecode(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entityRe, (m) {
    final body = m.group(1)!;
    final full = m.group(0)!;
    if (body.startsWith('#')) {
      final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(isHex ? body.substring(2) : body.substring(1), radix: isHex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return full;
      return String.fromCharCode(code);
    }
    // Named entities without the trailing ';' are only accepted for the classic four (as browsers do for legacy names).
    final hasSemi = full.endsWith(';');
    final v = _named[body];
    if (v == null) return full;
    if (!hasSemi && !const {'amp', 'lt', 'gt', 'quot', 'nbsp', 'copy', 'reg'}.contains(body)) return full;
    return v;
  });
}

/// `java.htmlEncode`-like escaping of the five XML characters.
String htmlEncode(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
