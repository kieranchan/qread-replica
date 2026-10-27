// util/legado/html_formatter.dart - Legado `HtmlFormatter`: turns the HTML of a chapter into plain paragraphs (`\n` + two ideographic
// spaces as indent), optionally keeping `<img>` tags with absolute URLs.
import '../webbook/util/network_utils.dart';

class HtmlFormatter {
  // Legado runs on Android, whose (ICU) `\s` is Unicode-aware like Dart's: it also matches U+3000 and NBSP. That is what makes
  // `^[\n\s]+` swallow the indent produced by the first step instead of doubling it.
  static final RegExp _wrapHtml = RegExp(r'</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>');
  static final RegExp _comment = RegExp(r'<!--[^>]*-->');
  static final RegExp _notImgHtml = RegExp(r'</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>');
  static final RegExp _otherHtml = RegExp(r'</?[a-zA-Z]+(?=[ >])[^<>]*>');
  static final RegExp _formatImage = RegExp(r'''<img[^>]*src="([^"]*(?:"[^>]+\})?)"[^>]*>''', caseSensitive: false);
  static final RegExp _indent1 = RegExp(r'\s*\n+\s*');
  static final RegExp _indent2 = RegExp(r'^[\n\s]+');
  static final RegExp _last = RegExp(r'[\n\s]+$');

  static const String indent = '　　';

  static String format(String? html, {RegExp? otherRegex}) {
    if (html == null) return '';
    return html
        .replaceAll(_wrapHtml, '\n')
        .replaceAll(_comment, '')
        .replaceAll(otherRegex ?? _otherHtml, '')
        .replaceAll(_indent1, '\n$indent')
        .replaceAll(_indent2, indent)
        .replaceAll(_last, '');
  }

  static String formatKeepImg(String? html, {String? redirectUrl}) {
    if (html == null) return '';
    final keep = html
        .replaceAll(_wrapHtml, '\n')
        .replaceAll(_comment, '')
        .replaceAll(_notImgHtml, '')
        .replaceAll(_indent1, '\n$indent')
        .replaceAll(_indent2, indent)
        .replaceAll(_last, '');
    final sb = StringBuffer();
    var appendPos = 0;
    for (final m in _formatImage.allMatches(keep)) {
      sb.write(keep.substring(appendPos, m.start));
      sb.write('<img src="${NetworkUtils.getAbsoluteURL(redirectUrl, m.group(1) ?? '')}">');
      appendPos = m.end;
    }
    if (appendPos < keep.length) sb.write(keep.substring(appendPos));
    return sb.toString();
  }

  /// Strips tags and keeps line structure without the indent (used for intro texts in lists).
  static String stripTags(String? html) {
    if (html == null) return '';
    return html.replaceAll(_wrapHtml, '\n').replaceAll(_comment, '').replaceAll(_otherHtml, '').trim();
  }
}
