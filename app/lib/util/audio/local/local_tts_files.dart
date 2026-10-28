// util/audio/local/local_tts_files.dart — model packages on disk, the parts of the original ai/local_tts.dart that need no engine:
//   * import (worker job 0xfe67bc, called from 0xfe6058 with {zipPath, tmpPath, finalRoot, existingNames}): unpack into
//     `<local_tts>/.importing`, read `tts.json` (`模型不正确` when it is missing or not an object), refuse a name that exists
//     (`模型「x」已导入，请勿重复操作`), check the files the engine needs (`模型包缺少 …`), move the folder to `<local_tts>/<name>/`;
//     failures come back as {success: false, error} (`fail` 0xfe8500) and the staging folder is removed.
//   * the engine config of an installed model (0x20f028): which .onnx is the acoustic model / encoder / decoder / vocos vocoder,
//     lexicon(s), tokens, espeak-ng-data, jieba `dict`, rule FSTs (comma-joined); `模型文件不存在（…）` when one is missing.
//   * WAV in and out: the worker writes RIFF/WAVE PCM-16 mono (0x2010d8); clone reference audio must be a PCM-16 WAV (0x20ea18:
//     `参考音频仅支持 WAV 格式` / `参考音频仅支持 PCM 16 位 WAV`), passed as `data:audio/wav;base64,…` in the engine page.
// Replica additions (marked): the official k2-fsa release archives are `.tar.bz2` without `tts.json`, so besides the original's
// `.zip` the importer unpacks tar archives and, when `tts.json` is missing, writes one from the files ([inferManifest]); a vocos
// vocoder `.onnx` can be installed on its own into `<local_tts>/_shared/` and is used by matcha / zipvoice packages that ship
// without one (the release archives do). The original's de-duplication of shared resources (`_shared` + `_refs.json` reference
// counts, `SHARED:<dir>` paths, `_migrated`, 0xe9b5b4 / 0x214990) is not reproduced: every model keeps its own espeak-ng-data / dict.
//
// Everything here is plain dart:io so the import runs in a background isolate ([LocalTtsFiles.importPackage]).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'local_tts_model.dart';

/// A failure with a user-facing (original) message.
class LocalTtsError implements Exception {
  final String message;
  const LocalTtsError(this.message);
  @override
  String toString() => message;
}

abstract class LocalTtsFiles {
  static const String rootName = 'local_tts';
  static const String registryName = 'registry.json';
  static const String manifestName = 'tts.json';
  static const String sharedName = '_shared';
  static const String importingName = '.importing';

  /// Archive types the importer unpacks (`.zip` is the original's; the tar family is a replica addition).
  static const List<String> archiveExtensions = ['.zip', '.tar.bz2', '.tbz', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar'];

  static bool isArchive(String path) {
    final l = path.toLowerCase();
    return archiveExtensions.any(l.endsWith);
  }

  /// A standalone vocos vocoder (`vocos-22khz-univ.onnx`, `vocos_24khz.onnx`).
  static bool isVocoderFile(String path) {
    final b = p.basename(path).toLowerCase();
    return b.endsWith('.onnx') && b.contains('vocos');
  }

  /// Names a model folder may not have (path tricks, the registry's own entries).
  static bool validName(String name) {
    final n = name.trim();
    return n.isNotEmpty &&
        !n.contains('/') &&
        !n.contains(r'\') &&
        !n.contains('..') &&
        !n.startsWith('.') &&
        n != sharedName &&
        n != registryName;
  }

  // ------------------------------------------------------------------ import

  /// Imports one package (runs in a background isolate). [req]: `zipPath`, `tmpPath`, `finalRoot`, `existingNames`, `sharedDir`.
  /// Returns {success: true, name, type, engine, voices, size} or {success: false, error}.
  static Future<Map<String, Object?>> importPackage(Map<String, Object?> req) async {
    final zipPath = '${req['zipPath'] ?? ''}';
    final tmp = Directory('${req['tmpPath'] ?? ''}');
    final finalRoot = '${req['finalRoot'] ?? ''}';
    final existing = [for (final e in (req['existingNames'] as List?) ?? const []) '$e'];
    final shared = '${req['sharedDir'] ?? ''}';
    Map<String, Object?> fail(String error) {
      _delete(tmp);
      return {'success': false, 'error': error};
    }

    try {
      _delete(tmp);
      tmp.createSync(recursive: true);
      try {
        await extractFileToDisk(zipPath, tmp.path);
      } catch (_) {
        return fail('模型不正确');
      }
      final root = packageRoot(tmp);
      Map<String, dynamic>? manifest;
      final mf = File(p.join(root.path, manifestName));
      if (mf.existsSync()) {
        try {
          final v = jsonDecode(utf8.decode(mf.readAsBytesSync(), allowMalformed: true));
          if (v is Map) manifest = Map<String, dynamic>.from(v);
        } catch (_) {}
        if (manifest == null) return fail('模型不正确');
      } else {
        // replica: release archives carry no tts.json
        manifest = inferManifest(root, root.path == tmp.path ? _stem(zipPath) : p.basename(root.path));
        if (manifest == null) return fail('模型不正确');
      }
      final model = LocalTtsModel.fromJson(manifest);
      final name = model.name.trim();
      if (!validName(name) || !LocalTtsEngines.all.contains(model.engine)) return fail('模型不正确');
      if (existing.contains(name)) return fail('模型「$name」已导入，请勿重复操作');
      final missing = validate(root, model.engine, sharedDir: shared);
      if (missing != null) return fail(missing);

      final dest = Directory(p.join(finalRoot, name));
      _delete(dest);
      Directory(finalRoot).createSync(recursive: true);
      try {
        root.renameSync(dest.path);
      } on FileSystemException {
        _copyDir(root, dest);
      }
      model.name = name;
      File(p.join(dest.path, manifestName)).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        ...manifest,
        'name': name,
        'engine': model.engine,
        'voices': [for (final v in model.voices) v.toJson()],
      }));
      final size = dirSize(dest);
      _delete(tmp);
      return {
        'success': true,
        'name': name,
        'type': model.type,
        'engine': model.engine,
        'voices': [for (final v in model.voices) v.toJson()],
        'size': size,
      };
    } catch (e) {
      return fail('$e');
    }
  }

  /// The folder of an unpacked archive that holds the package: the one with `tts.json`, else the single sub-folder the archive
  /// wraps everything in (release archives: `vits-melo-tts-zh_en/…`).
  static Directory packageRoot(Directory dir) {
    var d = dir;
    for (var depth = 0; depth < 4; depth++) {
      if (File(p.join(d.path, manifestName)).existsSync()) return d;
      final kids = d.listSync().where((e) => !p.basename(e.path).startsWith('.') && p.basename(e.path) != '__MACOSX').toList();
      final files = kids.whereType<File>().toList();
      final dirs = kids.whereType<Directory>().toList();
      if (files.isEmpty && dirs.length == 1) {
        d = dirs.single;
        continue;
      }
      return d;
    }
    return d;
  }

  /// What is missing for [engine] in an unpacked package (the original's `模型包缺少 …` messages), null when complete.
  static String? validate(Directory dir, String engine, {String sharedDir = ''}) {
    final f = _Listing(dir);
    if (!f.has('tokens.txt')) return '模型包缺少 tokens.txt';
    switch (engine) {
      case LocalTtsEngines.zipvoice:
        if (!f.has('lexicon.txt')) return '模型包缺少 lexicon.txt';
        if (f.onnxWhere((b) => b.contains('encoder')) == null) return '模型包缺少 encoder（.onnx）';
        if (f.onnxWhere((b) => b.contains('decoder')) == null) return '模型包缺少 decoder（.onnx）';
        if (f.vocoder(sharedDir, prefer: '24') == null) return '模型包缺少 vocoder（vocos .onnx）';
      case LocalTtsEngines.matcha:
        if (f.onnxWhere((b) => !b.contains('vocos')) == null || f.vocoder(sharedDir, prefer: '22') == null) return '模型包缺少声学模型或 vocoder（.onnx）';
        if (!f.has('lexicon.txt') && !f.hasDir('espeak-ng-data')) return '模型包缺少 lexicon.txt';
      case LocalTtsEngines.vits:
        if (f.onnx.isEmpty) return '模型包缺少 .onnx 模型文件';
        if (!f.has('lexicon.txt') && !f.hasDir('espeak-ng-data')) return '模型包缺少 lexicon.txt';
      case LocalTtsEngines.kokoro:
        if (!f.hasDir('espeak-ng-data')) return '模型包缺少 espeak-ng-data';
        if (f.onnx.isEmpty) return '模型包缺少 .onnx 模型文件';
        if (!f.has('voices.bin')) return '模型包缺少 voices.bin';
      default:
        return '模型不正确';
    }
    return null;
  }

  // ------------------------------------------------------------------ engine config (0x20f028)

  /// The paths the engine of an installed model needs, keyed as the worker message of the original: engine, model, encoder,
  /// decoder, vocoder, lexicon, tokens, dataDir, ruleFsts, dictDir, voices. Throws [LocalTtsError] (`模型文件不存在（…）`).
  static Map<String, String> modelConfig(Directory dir, String engine, {String sharedDir = ''}) {
    if (!dir.existsSync()) throw LocalTtsError('本地模型不存在：${p.basename(dir.path)}');
    final f = _Listing(dir);
    String need(String file, String error) {
      if (!f.has(file)) throw LocalTtsError(error);
      return p.join(dir.path, file);
    }

    String opt(String file) => f.has(file) ? p.join(dir.path, file) : '';
    final dataDir = f.hasDir('espeak-ng-data') ? p.join(dir.path, 'espeak-ng-data') : '';
    final dictDir = f.hasDir('dict') ? p.join(dir.path, 'dict') : '';
    final fsts = [for (final n in f.files) if (n.toLowerCase().endsWith('.fst')) p.join(dir.path, n)]..sort();
    final c = <String, String>{
      'engine': engine,
      'model': '',
      'encoder': '',
      'decoder': '',
      'vocoder': '',
      'lexicon': '',
      'tokens': '',
      'dataDir': dataDir,
      'ruleFsts': fsts.join(','),
      'dictDir': dictDir,
      'voices': '',
    };
    switch (engine) {
      case LocalTtsEngines.zipvoice:
        c['encoder'] = f.onnxWhere((b) => b.contains('encoder')) ?? (throw const LocalTtsError('模型文件不存在（encoder .onnx）'));
        c['decoder'] = f.onnxWhere((b) => b.contains('decoder')) ?? (throw const LocalTtsError('模型文件不存在（decoder .onnx）'));
        c['vocoder'] = f.vocoder(sharedDir, prefer: '24') ?? (throw const LocalTtsError('模型文件不存在（vocoder .onnx）'));
        c['lexicon'] = need('lexicon.txt', '模型文件不存在（lexicon.txt）');
        c['tokens'] = need('tokens.txt', '模型文件不存在（tokens.txt）');
      case LocalTtsEngines.vits:
        c['model'] = f.onnxWhere((b) => b == 'model.onnx') ??
            f.onnxWhere((b) => !b.contains('int8')) ??
            f.onnxWhere((_) => true) ??
            (throw const LocalTtsError('模型文件不存在（.onnx）'));
        c['lexicon'] = dataDir.isEmpty ? need('lexicon.txt', '模型文件不存在（lexicon.txt）') : opt('lexicon.txt');
        c['tokens'] = need('tokens.txt', '模型文件不存在（tokens.txt）');
      case LocalTtsEngines.matcha:
        c['model'] = f.onnxWhere((b) => !b.contains('vocos')) ?? (throw const LocalTtsError('模型文件不存在（声学模型 .onnx）'));
        c['vocoder'] = f.vocoder(sharedDir, prefer: '22') ?? (throw const LocalTtsError('模型文件不存在（vocoder .onnx）'));
        c['lexicon'] = dataDir.isEmpty ? need('lexicon.txt', '模型文件不存在（lexicon.txt）') : opt('lexicon.txt');
        c['tokens'] = need('tokens.txt', '模型文件不存在（tokens.txt）');
      case LocalTtsEngines.kokoro:
        c['model'] = f.onnxWhere((b) => b == 'model.onnx') ?? f.onnxWhere((_) => true) ?? (throw const LocalTtsError('模型文件不存在（model.onnx）'));
        c['voices'] = need('voices.bin', '模型文件不存在（voices.bin）');
        c['tokens'] = need('tokens.txt', '模型文件不存在（tokens.txt）');
        if (dataDir.isEmpty) throw const LocalTtsError('模型目录不存在（espeak-ng-data）');
        final lex = [for (final n in const ['lexicon-us-en.txt', 'lexicon-zh.txt']) if (f.has(n)) p.join(dir.path, n)];
        c['lexicon'] = lex.isEmpty ? opt('lexicon.txt') : lex.join(',');
      default:
        throw const LocalTtsError('模型不正确');
    }
    return c;
  }

  // ------------------------------------------------------------------ manifest inference (replica)

  /// Bytes one kokoro speaker takes in `voices.bin` (510 × 256 float32).
  static const int kokoroVoiceBytes = 510 * 256 * 4;

  /// Speaker names of the kokoro releases (sherpa-onnx docs), by speaker count.
  static const Map<int, List<String>> kokoroSpeakers = {
    11: ['af', 'af_bella', 'af_nicole', 'af_sarah', 'af_sky', 'am_adam', 'am_michael', 'bf_emma', 'bf_isabella', 'bm_george', 'bm_lewis'],
    53: [
      'af_alloy', 'af_aoede', 'af_bella', 'af_heart', 'af_jessica', 'af_kore', 'af_nicole', 'af_nova', 'af_river', 'af_sarah', //
      'af_sky', 'am_adam', 'am_echo', 'am_eric', 'am_fenrir', 'am_liam', 'am_michael', 'am_onyx', 'am_puck', 'am_santa', //
      'bf_alice', 'bf_emma', 'bf_isabella', 'bf_lily', 'bm_daniel', 'bm_fable', 'bm_george', 'bm_lewis', 'ef_dora', 'em_alex', //
      'ff_siwis', 'hf_alpha', 'hf_beta', 'hm_omega', 'hm_psi', 'if_sara', 'im_nicola', 'jf_alpha', 'jf_gongitsune', 'jf_nezumi', //
      'jf_tebukuro', 'jm_kumo', 'pf_dora', 'pm_alex', 'pm_santa', 'zf_xiaobei', 'zf_xiaoni', 'zf_xiaoxiao', 'zf_xiaoyi', 'zm_yunjian', //
      'zm_yunxi', 'zm_yunxia', 'zm_yunyang',
    ],
  };

  /// Speaker counts of multi-speaker vits releases (the count is not in the files).
  static const Map<String, int> vitsSpeakers = {'vits-zh-hf-fanchen-C': 187, 'vits-icefall-zh-aishell3': 174};

  static const Map<String, String> _kokoroLang = {
    'a': 'en-US', 'b': 'en-GB', 'e': 'es', 'f': 'fr', 'h': 'hi', 'i': 'it', 'j': 'ja', 'p': 'pt-BR', 'z': 'zh', //
  };

  /// A `tts.json` for a package that has none (release archives): the engine from the files, voices from `voices.bin` (kokoro), the
  /// known speaker count (vits) or one default voice; zipvoice has none (clone). Null when the files match no engine.
  static Map<String, dynamic>? inferManifest(Directory dir, String name) {
    final f = _Listing(dir);
    final lower = name.toLowerCase();
    final String engine;
    if (f.has('voices.bin') && f.onnx.isNotEmpty) {
      engine = LocalTtsEngines.kokoro;
    } else if (f.onnxWhere((b) => b.contains('encoder')) != null && f.onnxWhere((b) => b.contains('decoder')) != null) {
      engine = LocalTtsEngines.zipvoice;
    } else if (lower.contains('matcha') || (f.onnxWhere((b) => b.contains('vocos')) != null && f.onnx.length > 1)) {
      engine = LocalTtsEngines.matcha;
    } else if (f.onnx.isNotEmpty) {
      engine = LocalTtsEngines.vits;
    } else {
      return null;
    }
    final lang = lower.contains('zh') || lower.contains('aishell') || lower.contains('baker') ? 'zh' : 'en';
    final voices = <Map<String, dynamic>>[];
    switch (engine) {
      case LocalTtsEngines.kokoro:
        final n = math.max(1, File(p.join(dir.path, 'voices.bin')).lengthSync() ~/ kokoroVoiceBytes);
        final names = kokoroSpeakers[n];
        for (var i = 0; i < n; i++) {
          final s = names?[i] ?? '';
          voices.add({
            'id': i,
            'name': s.isEmpty ? '音色 $i' : s,
            'lang': s.length > 2 ? (_kokoroLang[s[0]] ?? lang) : lang,
            'gender': s.length > 2 ? (s[1] == 'f' ? 'female' : (s[1] == 'm' ? 'male' : '')) : '',
          });
        }
      case LocalTtsEngines.zipvoice:
        break;
      default:
        final n = vitsSpeakers[name] ?? 1;
        for (var i = 0; i < n; i++) {
          voices.add({'id': i, 'name': n == 1 ? '默认' : '音色 $i', 'lang': lang, 'gender': ''});
        }
    }
    return {'name': name, 'type': 0, 'engine': engine, 'lang': lang, 'voices': voices};
  }

  // ------------------------------------------------------------------ WAV

  /// RIFF/WAVE, PCM 16-bit mono (0x2010d8).
  static Uint8List wavBytes(Float32List samples, int sampleRate) {
    final n = samples.length;
    final b = ByteData(44 + n * 2);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    b.setUint32(4, 36 + n * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    b.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final s = samples[i].isNaN ? 0.0 : samples[i].clamp(-1.0, 1.0);
      b.setInt16(44 + i * 2, (s * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// Samples (mono, -1..1) and the sample rate of a PCM-16 WAV (0x20ea18); several channels are averaged.
  static ({Float32List samples, int sampleRate}) readWav(Uint8List bytes) {
    String tag(int at) => at + 4 <= bytes.length ? String.fromCharCodes(bytes.sublist(at, at + 4)) : '';
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') throw const LocalTtsError('参考音频仅支持 WAV 格式');
    final b = ByteData.sublistView(bytes);
    var at = 12;
    int? format, channels, rate, bits;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      final size = b.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = b.getUint16(body, Endian.little);
        channels = b.getUint16(body + 2, Endian.little);
        rate = b.getUint32(body + 4, Endian.little);
        bits = b.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (format != 1 || bits != 16 || channels == null || channels < 1 || rate == null) {
          throw const LocalTtsError('参考音频仅支持 PCM 16 位 WAV');
        }
        final end = math.min(bytes.length, body + size);
        final frames = (end - body) ~/ (2 * channels);
        final out = Float32List(frames);
        for (var i = 0; i < frames; i++) {
          var sum = 0;
          for (var c = 0; c < channels; c++) {
            sum += b.getInt16(body + (i * channels + c) * 2, Endian.little);
          }
          out[i] = sum / channels / 32768.0;
        }
        return (samples: out, sampleRate: rate);
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    throw const LocalTtsError('参考音频仅支持 PCM 16 位 WAV');
  }

  /// The bytes of a `data:<mime>;base64,<…>` URI (or of plain base64); empty when there is nothing.
  static Uint8List dataUriBytes(String uri) {
    final s = uri.trim();
    if (s.isEmpty) return Uint8List(0);
    final i = s.startsWith('data:') ? s.indexOf(',') : -1;
    try {
      return base64Decode(i >= 0 ? s.substring(i + 1) : s);
    } on FormatException {
      return Uint8List(0);
    }
  }

  // ------------------------------------------------------------------ helpers

  static int dirSize(Directory d) {
    var n = 0;
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) n += e.lengthSync();
    }
    return n;
  }

  static String _stem(String path) {
    var b = p.basename(path);
    final l = b.toLowerCase();
    for (final ext in archiveExtensions) {
      if (l.endsWith(ext)) return b.substring(0, b.length - ext.length);
    }
    final dot = b.lastIndexOf('.');
    return dot > 0 ? b.substring(0, dot) : b;
  }

  static void _delete(FileSystemEntity e) {
    try {
      if (e.existsSync()) e.deleteSync(recursive: true);
    } catch (_) {}
  }

  static void _copyDir(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync(followLinks: false)) {
      final target = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        _copyDir(e, Directory(target));
      } else if (e is File) {
        e.copySync(target);
      }
    }
  }
}

/// The top level of a model folder.
class _Listing {
  final List<String> files;
  final List<String> dirs;
  final String path;
  _Listing._(this.path, this.files, this.dirs);

  factory _Listing(Directory d) {
    final files = <String>[], dirs = <String>[];
    if (d.existsSync()) {
      for (final e in d.listSync(followLinks: false)) {
        final b = p.basename(e.path);
        if (e is File) files.add(b);
        if (e is Directory) dirs.add(b);
      }
    }
    files.sort();
    return _Listing._(d.path, files, dirs);
  }

  bool has(String file) => files.contains(file);
  bool hasDir(String dir) => dirs.contains(dir);

  List<String> get onnx => [for (final f in files) if (f.toLowerCase().endsWith('.onnx')) f];

  /// Full path of the first `.onnx` whose lower-case name passes [test].
  String? onnxWhere(bool Function(String lowerName) test) {
    for (final f in onnx) {
      if (test(f.toLowerCase())) return p.join(path, f);
    }
    return null;
  }

  /// The vocos vocoder of the package, else one installed under `_shared` (the one whose name has [prefer], e.g. `22` for the
  /// 22.05 kHz matcha models, `24` for zipvoice, when several are installed).
  String? vocoder(String sharedDir, {String prefer = ''}) {
    final own = onnxWhere((b) => b.contains('vocos'));
    if (own != null || sharedDir.isEmpty) return own;
    final s = _Listing(Directory(sharedDir));
    return s.onnxWhere((b) => b.contains('vocos') && b.contains(prefer)) ?? s.onnxWhere((b) => b.contains('vocos'));
  }
}
