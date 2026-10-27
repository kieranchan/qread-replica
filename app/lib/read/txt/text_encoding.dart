// read/txt/text_encoding.dart — charset detection and decoding for local TXT files: UTF-8 (with/without BOM), UTF-16 LE/BE and
// GBK (GB2312 / GBK; GB18030 4-byte sequences are decoded as far as `fast_gbk` goes, i.e. not at all: see TextFile docs).
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

enum TextEncoding { utf8, utf16le, utf16be, gbk }

class TextEncodingInfo {
  final TextEncoding encoding;

  /// Length of the byte-order mark at the start of the file (0 when there is none).
  final int bomLength;

  const TextEncodingInfo(this.encoding, [this.bomLength = 0]);

  /// Name stored in `Book.charset`.
  String get charsetName => switch (encoding) {
        TextEncoding.utf8 => 'UTF-8',
        TextEncoding.utf16le => 'UTF-16LE',
        TextEncoding.utf16be => 'UTF-16BE',
        TextEncoding.gbk => 'GBK',
      };

  /// Width of a code unit in bytes (line feed = this many bytes).
  int get unit => encoding == TextEncoding.utf16le || encoding == TextEncoding.utf16be ? 2 : 1;

  @override
  String toString() => charsetName;
}

abstract class TextEncodings {
  /// Maps a charset name (`Book.charset`, user choice) to an encoding; null for "auto" / unknown names.
  static TextEncodingInfo? fromName(String? name) {
    final n = (name ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (n.isEmpty || n == 'auto') return null;
    if (n == 'utf-8' || n == 'utf8') return const TextEncodingInfo(TextEncoding.utf8);
    if (n == 'utf-16le' || n == 'utf-16') return const TextEncodingInfo(TextEncoding.utf16le);
    if (n == 'utf-16be') return const TextEncodingInfo(TextEncoding.utf16be);
    if (n.startsWith('gb') || n == 'cp936' || n == 'big5-gbk') return const TextEncodingInfo(TextEncoding.gbk);
    return null;
  }

  /// Detects the encoding from the first bytes of a file. A BOM wins; then UTF-16 without BOM (NUL bytes at every other
  /// position); then "strictly valid UTF-8" (pure ASCII counts); everything else is GBK.
  static TextEncodingInfo detect(Uint8List bytes, {String? hint}) {
    final forced = fromName(hint);
    if (forced != null) {
      return TextEncodingInfo(forced.encoding, _bomFor(bytes, forced.encoding));
    }
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) return const TextEncodingInfo(TextEncoding.utf8, 3);
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return const TextEncodingInfo(TextEncoding.utf16le, 2);
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return const TextEncodingInfo(TextEncoding.utf16be, 2);

    final n = bytes.length < 131072 ? bytes.length : 131072;
    if (n == 0) return const TextEncodingInfo(TextEncoding.utf8);
    var evenZero = 0;
    var oddZero = 0;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) {
        if (i.isEven) {
          evenZero++;
        } else {
          oddZero++;
        }
      }
    }
    final half = n / 2;
    if (oddZero > half * 0.3 && evenZero < half * 0.05) return const TextEncodingInfo(TextEncoding.utf16le);
    if (evenZero > half * 0.3 && oddZero < half * 0.05) return const TextEncodingInfo(TextEncoding.utf16be);

    return _validUtf8(bytes, n) ? const TextEncodingInfo(TextEncoding.utf8) : const TextEncodingInfo(TextEncoding.gbk);
  }

  static int _bomFor(Uint8List b, TextEncoding e) {
    switch (e) {
      case TextEncoding.utf8:
        return b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF ? 3 : 0;
      case TextEncoding.utf16le:
        return b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE ? 2 : 0;
      case TextEncoding.utf16be:
        return b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF ? 2 : 0;
      case TextEncoding.gbk:
        return 0;
    }
  }

  /// Strict UTF-8 validation of the first [n] bytes (a sequence cut off by the end of the sample is tolerated).
  static bool _validUtf8(Uint8List b, int n) {
    var i = 0;
    while (i < n) {
      final c = b[i];
      if (c < 0x80) {
        i++;
        continue;
      }
      int need;
      if (c >= 0xC2 && c <= 0xDF) {
        need = 1;
      } else if (c >= 0xE0 && c <= 0xEF) {
        need = 2;
      } else if (c >= 0xF0 && c <= 0xF4) {
        need = 3;
      } else {
        return false;
      }
      for (var k = 1; k <= need; k++) {
        if (i + k >= n) {
          // truncated by the sample window: only fine when the sample is a prefix of a longer file
          return n < b.length;
        }
        if ((b[i + k] & 0xC0) != 0x80) return false;
      }
      if (c == 0xE0 && b[i + 1] < 0xA0) return false;
      if (c == 0xED && b[i + 1] > 0x9F) return false;
      if (c == 0xF0 && b[i + 1] < 0x90) return false;
      if (c == 0xF4 && b[i + 1] > 0x8F) return false;
      i += need + 1;
    }
    return true;
  }

  /// Decodes `bytes[start, end)` (malformed sequences become U+FFFD / the GBK replacement).
  static String decode(Uint8List bytes, TextEncoding enc, [int start = 0, int? end]) {
    final e = end ?? bytes.length;
    if (e <= start) return '';
    switch (enc) {
      case TextEncoding.utf8:
        return utf8.decode(Uint8List.sublistView(bytes, start, e), allowMalformed: true);
      case TextEncoding.gbk:
        return gbk.decode(Uint8List.sublistView(bytes, start, e), allowMalformed: true);
      case TextEncoding.utf16le:
      case TextEncoding.utf16be:
        final le = enc == TextEncoding.utf16le;
        final len = (e - start) ~/ 2;
        final units = Uint16List(len);
        for (var i = 0; i < len; i++) {
          final a = bytes[start + 2 * i];
          final b = bytes[start + 2 * i + 1];
          units[i] = le ? (b << 8) | a : (a << 8) | b;
        }
        return String.fromCharCodes(units);
    }
  }
}
