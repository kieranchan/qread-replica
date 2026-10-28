// pages/tts/local/local_engines.dart — what the 本地引擎 sheet does besides drawing (the original keeps it in tts_setting.dart):
//   * a voice becomes a page engine with id `bdtts_<model>_<voice id>` (sub_609aec) made from the bdtts template (0x609b74):
//     `该音色引擎已存在` / `已添加：<name>` / `添加失败：<e>` (0xfe3cbc); the voice list marks voices that have one (`已添加`)
//   * a clone engine (0xfe49bc): the reference text is required (`请先填写参考音频中说的文字`), default name `克隆音色`, bdttsclone
//     template (0x60b4e0) with the reference WAV as a data URI (`data:audio/wav;base64,`, 0xfe4698, `读取音频失败：`)
//   * previews call the manager directly (no member gate, like the original 0xfe419c / 0xfe4c30): `你好，这是本地朗读引擎的试听语音。`
//     for Chinese voices, `Hello, this is a local TTS voice preview.` otherwise, `你好，这是克隆音色的试听语音。` for clones; played
//     from `<documents>/audio/bdtts_preview.wav` / `bdtts_clone_preview.wav`; `试听失败：<e>`
//   * settings checks (0xfe5800 / 0xfe5544): `线程数必须在 1 ~ <cores> 之间`, `步数必须在 1 ~ 50 之间`
//   * import messages (0xfe5b2c): `已导入模型：<name>（<n> 款音色，<size> MB）` and, above 150 MB, `模型较大，内存小的手机朗读时可能被系统回收，
//     建议使用 150MB 内的模型（matcha/vits 系列）`
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../common/app_dirs.dart';
import '../../../data/tts.dart';
import '../../../models/httptts.dart';
import '../../../util/audio/local/local_tts_files.dart';
import '../../../util/audio/local/local_tts_manager.dart';
import '../../../util/audio/my_audio_player.dart';
import '../../../util/audio/tts_page.dart';
import '../../../util/toast.dart';

/// A picked reference recording of a clone engine.
class CloneReference {
  final String fileName;
  final String dataUri;
  final double seconds;
  const CloneReference(this.fileName, this.dataUri, this.seconds);
}

abstract class LocalEngines {
  static const String previewZh = '你好，这是本地朗读引擎的试听语音。';
  static const String previewEn = 'Hello, this is a local TTS voice preview.';
  static const String previewClone = '你好，这是克隆音色的试听语音。';
  static const String bigModel = '\n模型较大，内存小的手机朗读时可能被系统回收，建议使用 150MB 内的模型（matcha/vits 系列）';

  /// `bdtts_<model>_<voice id>` (sub_609aec).
  static String engineId(String model, int voiceId) => 'bdtts_${model}_$voiceId';

  /// The local model a page engine speaks with (bdtts / bdttsclone pages), null for other engines.
  static String? modelOf(HttpTts e) {
    final page = TTSData.pageOf(e);
    if (page.isEmpty) return null;
    final r = TtsPages.literal(page);
    return r != null && (r.method == 'bdtts' || r.method == 'bdttsclone') ? r.url : null;
  }

  /// The distinct local models of the engines [ids] (multi-role setups warn when there is more than one).
  static List<String> modelsOf(Iterable<String> ids) {
    final out = <String>[];
    for (final id in ids) {
      final e = TTSData.byId(id);
      final m = e == null ? null : modelOf(e);
      if (m != null && !out.contains(m)) out.add(m);
    }
    return out;
  }

  static bool exists(String model, int voiceId) {
    final id = engineId(model, voiceId);
    return TTSData.engines.any((e) => e.id == id);
  }

  /// Default name offered in 命名朗读引擎.
  static String defaultName(LocalTtsModel m, LocalTtsVoice v) => v.name.trim().isEmpty ? '${m.name}-${v.id}' : v.name.trim();

  /// Adds the engine of one voice; null when it exists or failed (toasts as the original).
  static Future<HttpTts?> addVoice(LocalTtsModel m, LocalTtsVoice v, String name) async {
    final n = name.trim().isEmpty ? defaultName(m, v) : name.trim();
    try {
      await TTSData.load();
      if (exists(m.name, v.id)) {
        Toast.show('该音色引擎已存在');
        return null;
      }
      final e = await Tts.add(HttpTts(id: engineId(m.name, v.id), name: n, tp: 0, candel: true, html: {'page': TtsPages.localPage(m.name, '${v.id}')}));
      Toast.show('已添加：$n');
      return e;
    } catch (e) {
      Toast.show('添加失败：$e', iserror: true);
      return null;
    }
  }

  /// Adds a clone engine of a zipvoice model.
  static Future<HttpTts?> addClone(LocalTtsModel m, {required String name, required CloneReference? reference, required String refText}) async {
    if (refText.trim().isEmpty) {
      Toast.show('请先填写参考音频中说的文字');
      return null;
    }
    if (reference == null) {
      Toast.show('克隆引擎缺少参考音频', iserror: true);
      return null;
    }
    final n = name.trim().isEmpty ? '克隆音色' : name.trim();
    try {
      await TTSData.load();
      final e = await Tts.add(HttpTts(name: n, tp: 0, candel: true, html: {'page': TtsPages.localClonePage(m.name, refText.trim(), reference.dataUri)}));
      Toast.show('已添加：$n');
      return e;
    } catch (e) {
      Toast.show('添加失败：$e', iserror: true);
      return null;
    }
  }

  /// Reads a picked WAV as the reference of a clone (PCM-16 WAV only).
  static CloneReference? readReference(File f) {
    try {
      final bytes = f.readAsBytesSync();
      final w = LocalTtsFiles.readWav(bytes);
      return CloneReference(f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last, 'data:audio/wav;base64,${base64Encode(bytes)}',
          w.sampleRate == 0 ? 0 : w.samples.length / w.sampleRate);
    } catch (e) {
      Toast.show('读取音频失败：$e', iserror: true);
      return null;
    }
  }

  static String previewText(LocalTtsVoice v) => v.lang.toLowerCase().startsWith('zh') ? previewZh : previewEn;

  static Myaudioplayer? _player;

  /// Synthesizes and plays a preview; false when it failed (`试听失败：<e>`).
  static Future<bool> preview(LocalTtsModel m, {LocalTtsVoice? voice, CloneReference? reference, String refText = ''}) async {
    try {
      final Uint8List wav;
      if (m.isClone) {
        if (refText.trim().isEmpty) {
          Toast.show('请先填写参考音频中说的文字');
          return false;
        }
        wav = await LocalTtsEngine.instance.synthesize(m.name, 0, previewClone, referenceAudioDataUri: reference?.dataUri ?? '', referenceText: refText.trim());
      } else {
        final v = voice ?? (m.voices.isEmpty ? LocalTtsVoice() : m.voices.first);
        wav = await LocalTtsEngine.instance.synthesize(m.name, v.id, previewText(v));
      }
      final p = _player ??= Myaudioplayer();
      await p.stop();
      await p.setBytes(wav, AppDirs.dir('audio'), m.isClone ? 'bdtts_clone_preview.wav' : 'bdtts_preview.wav');
      await p.play();
      return true;
    } catch (e) {
      Toast.show('试听失败：$e', iserror: true);
      return false;
    }
  }

  static Future<void> stopPreview() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// `线程数必须在 1 ~ n 之间` (null = default, fine).
  static String? checkThreads(int? n) {
    final max = LocalTtsManager.maxThreads;
    return n == null || (n >= 1 && n <= max) ? null : '线程数必须在 1 ~ $max 之间';
  }

  /// `步数必须在 1 ~ 50 之间` (null = default 4).
  static String? checkSteps(int? n) => n == null || (n >= 1 && n <= 50) ? null : '步数必须在 1 ~ 50 之间';

  /// Saves both settings (0xfe5358): `设置已保存` / `设置失败：<e>`.
  static Future<bool> saveSettings(LocalTtsModel m, {int? threads, int? steps}) async {
    try {
      final bad = checkThreads(threads) ?? checkSteps(steps);
      if (bad != null) throw LocalTtsError(bad);
      await LocalTtsManager.setNumThreads(m.name, threads);
      if (m.isClone) await LocalTtsManager.setNumSteps(m.name, steps);
      Toast.show('设置已保存');
      return true;
    } catch (e) {
      Toast.show('设置失败：$e', iserror: true);
      return false;
    }
  }

  /// The message after an import.
  static String importedMessage(LocalTtsImported r) {
    final mb = r.megabytes;
    return '已导入模型：${r.model.name}（${r.model.voices.length} 款音色，${mb.toStringAsFixed(1)} MB）${mb > 150 ? bigModel : ''}';
  }

  /// Imports a package or a vocoder file and toasts the outcome; true on success.
  static Future<bool> importFile(String path) async {
    try {
      if (LocalTtsFiles.isVocoderFile(path)) {
        final name = await LocalTtsManager.importShared(path);
        Toast.show('已导入声码器：$name');
        return true;
      }
      final r = await LocalTtsManager.importZip(path);
      Toast.show(importedMessage(r));
      return true;
    } catch (e) {
      Toast.show('导入失败：$e', iserror: true);
      return false;
    }
  }

  /// Deletes a model (0xfe2ff4): `已删除模型，由它生成的朗读引擎已保留` / `删除失败：<e>`.
  static Future<bool> deleteModel(String name) async {
    try {
      await LocalTtsManager.delete(name);
      Toast.show('已删除模型，由它生成的朗读引擎已保留');
      return true;
    } catch (e) {
      Toast.show('删除失败：$e', iserror: true);
      return false;
    }
  }

  /// `yyyy-MM-dd` of an import time.
  static String date(int ms) {
    if (ms <= 0) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
