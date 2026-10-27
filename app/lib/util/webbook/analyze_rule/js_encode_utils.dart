// util/webbook/analyze_rule/js_encode_utils.dart - the crypto/encoding natives behind `java.md5Encode`, `java.base64Decode`,
// `java.aesBase64DecodeToString`, `java.HMacHex` ... implemented in Dart (rule_engine.txt section 3a).
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import '../../http.dart';
import '../../legado/js_bindable.dart';
import '../util/network_utils.dart';

abstract class JsEncodeUtils {
  // hashes -----------------------------------------------------------------------------------------------------------------------
  static List<int> _utf8(String s) => utf8.encode(s);

  static crypto.Hash _hash(String algorithm) {
    final a = algorithm.toUpperCase().replaceAll('-', '').replaceAll('_', '');
    switch (a) {
      case 'MD5':
        return crypto.md5;
      case 'SHA1':
        return crypto.sha1;
      case 'SHA224':
        return crypto.sha224;
      case 'SHA256':
        return crypto.sha256;
      case 'SHA384':
        return crypto.sha384;
      case 'SHA512':
        return crypto.sha512;
    }
    throw JsHostError('NoSuchAlgorithmException: $algorithm');
  }

  static String md5Encode(String s) => crypto.md5.convert(_utf8(s)).toString();

  /// The middle 16 hex characters of the MD5 (`md5Encode16`).
  static String md5Encode16(String s) => md5Encode(s).substring(8, 24);

  static String sha1Encode(String s) => crypto.sha1.convert(_utf8(s)).toString();
  static String sha256Encode(String s) => crypto.sha256.convert(_utf8(s)).toString();
  static String sha512Encode(String s) => crypto.sha512.convert(_utf8(s)).toString();

  static String digestHex(String data, String algorithm) => _hash(algorithm).convert(_utf8(data)).toString();

  static String digestBase64(String data, String algorithm) => base64.encode(_hash(algorithm).convert(_utf8(data)).bytes);

  static String hmacHex(String data, String algorithm, String key) =>
      crypto.Hmac(_hash(algorithm.replaceFirst(RegExp('^Hmac', caseSensitive: false), '')), _utf8(key)).convert(_utf8(data)).toString();

  static String hmacBase64(String data, String algorithm, String key) =>
      base64.encode(crypto.Hmac(_hash(algorithm.replaceFirst(RegExp('^Hmac', caseSensitive: false), '')), _utf8(key)).convert(_utf8(data)).bytes);

  // base64 / hex ------------------------------------------------------------------------------------------------------------------
  static String base64Encode(String s) => base64.encode(_utf8(s));

  static String base64EncodeBytes(List<int> b) => base64.encode(b);

  /// Lenient: ignores whitespace, accepts url-safe alphabet and missing padding (Android `Base64.decode` is as tolerant).
  static Uint8List base64DecodeBytes(String s) {
    var t = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    final pad = t.length % 4;
    if (pad == 2) t += '==';
    if (pad == 3) t += '=';
    try {
      return base64.decode(t);
    } on FormatException catch (e) {
      throw JsHostError('IllegalArgumentException: bad base-64 (${e.message})');
    }
  }

  static String base64Decode(String s, [String charset = 'UTF-8']) => AppHttp.decodeWith(base64DecodeBytes(s), charset) ?? utf8.decode(base64DecodeBytes(s), allowMalformed: true);

  static String base64UrlEncode(String s) => base64Url.encode(_utf8(s));

  static String hexEncodeBytes(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static String hexEncode(String s) => hexEncodeBytes(_utf8(s));

  static Uint8List hexDecodeBytes(String hex) {
    final h = hex.replaceAll(RegExp(r'\s'), '');
    if (h.length.isOdd) throw JsHostError('IllegalArgumentException: odd hex length');
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final v = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
      if (v == null) throw JsHostError('IllegalArgumentException: bad hex digit');
      out[i] = v;
    }
    return out;
  }

  static String hexDecodeToString(String hex) => utf8.decode(hexDecodeBytes(hex), allowMalformed: true);

  static bool _looksHex(String s) => s.length.isEven && s.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);

  /// hutool `SecureUtil.decode`: hex when it looks like hex, base64 otherwise.
  static Uint8List decodeHexOrBase64(String s) => _looksHex(s) ? hexDecodeBytes(s) : base64DecodeBytes(s);

  // URL / escape ------------------------------------------------------------------------------------------------------------------
  /// `URLEncoder.encode(s, charset)`.
  static String urlEncode(String s, [String? charset]) => NetworkUtils.encodeBytes(AppHttp.encodeWith(s, charset));

  static String urlDecode(String s, [String? charset]) {
    final bytes = <int>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '+') {
        bytes.add(0x20);
        i++;
      } else if (c == '%' && i + 2 < s.length + 0 && int.tryParse(s.substring(i + 1, i + 3), radix: 16) != null) {
        bytes.add(int.parse(s.substring(i + 1, i + 3), radix: 16));
        i += 3;
      } else {
        bytes.addAll(utf8.encode(c));
        i++;
      }
    }
    return AppHttp.decodeWith(bytes, charset ?? 'utf-8') ?? utf8.decode(bytes, allowMalformed: true);
  }

  /// JavaScript `encodeURIComponent`.
  static String encodeURIComponent(String s) => Uri.encodeComponent(s).replaceAll('%20', '%20');

  /// JavaScript `encodeURI`.
  static String encodeURI(String s) => Uri.encodeFull(s);

  static const String _escapeSafe = r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./";

  /// JavaScript `escape()` (also the `charset: "escape"` URL option): `%XX` for Latin-1, `%uXXXX` above.
  static String escape(String s) {
    final sb = StringBuffer();
    for (final c in s.codeUnits) {
      if (c < 128 && _escapeSafe.contains(String.fromCharCode(c))) {
        sb.writeCharCode(c);
      } else if (c < 256) {
        sb.write('%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        sb.write('%u${c.toRadixString(16).toUpperCase().padLeft(4, '0')}');
      }
    }
    return sb.toString();
  }

  static String unescape(String s) => s.replaceAllMapped(RegExp(r'%u([0-9a-fA-F]{4})|%([0-9a-fA-F]{2})'), (m) {
        final v = int.parse(m.group(1) ?? m.group(2)!, radix: 16);
        return String.fromCharCode(v);
      });

  // symmetric ciphers ------------------------------------------------------------------------------------------------------------
  /// Runs a JCE-style transformation (`AES/CBC/PKCS5Padding`, `DES/ECB/NoPadding`, `DESede/CBC/PKCS7Padding` ...).
  /// A bare algorithm name means ECB + PKCS5 like Java.
  static Uint8List symmetric({
    required String transformation,
    required List<int> key,
    List<int>? iv,
    required List<int> data,
    required bool encrypt,
  }) {
    final parts = transformation.split('/');
    final alg = parts[0].trim().toUpperCase();
    final mode = (parts.length > 1 ? parts[1] : 'ECB').trim().toUpperCase();
    final padName = (parts.length > 2 ? parts[2] : 'PKCS5Padding').trim().toUpperCase();
    pc.BlockCipher engine;
    switch (alg) {
      case 'AES':
        if (!const [16, 24, 32].contains(key.length)) throw JsHostError('InvalidKeyException: Invalid AES key length: ${key.length} bytes');
        engine = pc.AESEngine();
        break;
      case 'DES':
        if (key.length != 8) throw JsHostError('InvalidKeyException: Wrong key size');
        // single DES == triple DES with K1 = K2 = K3 (pointycastle only exports the DESede engine)
        key = [...key, ...key, ...key];
        engine = pc.DESedeEngine();
        break;
      case 'DESEDE':
      case 'TRIPLEDES':
      case '3DES':
        if (key.length != 16 && key.length != 24) throw JsHostError('InvalidKeyException: Invalid key length: ${key.length} bytes');
        engine = pc.DESedeEngine();
        break;
      default:
        throw JsHostError('NoSuchAlgorithmException: $alg');
    }
    final bs = engine.blockSize;
    final keyParam = pc.KeyParameter(Uint8List.fromList(key));
    final ivBytes = Uint8List.fromList(_fitIv(iv ?? const [], bs));
    final needIv = mode != 'ECB';
    final ivParams = pc.ParametersWithIV<pc.CipherParameters>(keyParam, ivBytes);
    final pc.CipherParameters cipherParams = needIv ? ivParams : keyParam;

    if (mode == 'CTR') {
      final c = pc.CTRStreamCipher(engine)..init(encrypt, ivParams);
      return c.process(Uint8List.fromList(data));
    }
    pc.BlockCipher block;
    switch (mode) {
      case 'ECB':
        block = pc.ECBBlockCipher(engine);
        break;
      case 'CBC':
        block = pc.CBCBlockCipher(engine);
        break;
      case 'CFB':
        block = pc.CFBBlockCipher(engine, bs);
        break;
      case 'OFB':
        block = pc.OFBBlockCipher(engine, bs);
        break;
      default:
        throw JsHostError('NoSuchAlgorithmException: unsupported mode $mode');
    }
    final streamish = mode == 'CFB' || mode == 'OFB';
    if (padName.startsWith('NOPADDING') || streamish) {
      block.init(encrypt, cipherParams);
      if (streamish) {
        // CFB/OFB process any length
        final out = Uint8List(data.length);
        var off = 0;
        final inp = Uint8List.fromList(data);
        while (off < inp.length) {
          final n = (inp.length - off) >= bs ? bs : inp.length - off;
          final chunk = Uint8List(bs)..setRange(0, n, inp, off);
          final o = Uint8List(bs);
          block.processBlock(chunk, 0, o, 0);
          out.setRange(off, off + n, o);
          off += n;
        }
        return out;
      }
      if (data.length % bs != 0) throw JsHostError('IllegalBlockSizeException: input length not multiple of $bs');
      final inp = Uint8List.fromList(data);
      final out = Uint8List(inp.length);
      for (var off = 0; off < inp.length; off += bs) {
        block.processBlock(inp, off, out, off);
      }
      return out;
    }
    if (padName.startsWith('ZEROPADDING') || padName.startsWith('ZEROBYTEPADDING')) {
      block.init(encrypt, cipherParams);
      var inp = Uint8List.fromList(data);
      if (encrypt && inp.length % bs != 0) {
        final padded = Uint8List(((inp.length ~/ bs) + 1) * bs)..setRange(0, inp.length, inp);
        inp = padded;
      }
      if (inp.length % bs != 0) throw JsHostError('IllegalBlockSizeException: input length not multiple of $bs');
      final out = Uint8List(inp.length);
      for (var off = 0; off < inp.length; off += bs) {
        block.processBlock(inp, off, out, off);
      }
      if (encrypt) return out;
      var end = out.length;
      while (end > 0 && out[end - 1] == 0) {
        end--;
      }
      return Uint8List.sublistView(out, 0, end);
    }
    // PKCS5Padding / PKCS7Padding
    final padded = pc.PaddedBlockCipherImpl(pc.PKCS7Padding(), block);
    padded.init(encrypt, pc.PaddedBlockCipherParameters(cipherParams, null));
    try {
      return padded.process(Uint8List.fromList(data));
    } on ArgumentError catch (e) {
      throw JsHostError('BadPaddingException: ${e.message}');
    } on pc.InvalidCipherTextException catch (e) {
      throw JsHostError('BadPaddingException: ${e.message}');
    } on StateError catch (e) {
      throw JsHostError('IllegalBlockSizeException: ${e.message}');
    }
  }

  static List<int> _fitIv(List<int> iv, int size) {
    if (iv.length == size) return iv;
    final out = List<int>.filled(size, 0);
    for (var i = 0; i < size && i < iv.length; i++) {
      out[i] = iv[i];
    }
    return out;
  }
}
