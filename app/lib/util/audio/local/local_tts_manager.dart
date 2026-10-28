// util/audio/local/local_tts_manager.dart — `LocalTtsManager` of the original ai/local_tts.dart (class id 1664): installed models,
// import / delete / per-model settings, and synthesis through the worker isolate (local_tts_worker.dart) with the original's guards.
//
// Original statics: `_lock` 0x3958 (registry operations), `_synthLock` 0x3960 (one synthesis at a time), `_models` 0x3970,
// `_pending` 0x39a0 (request id → completer), `_watchdogs` 0x39a8, `_watchdogTimeout` 0x39b0 (180 s).
//   * registry `<documents>/local_tts/registry.json` (read error `本地TTS注册表读取失败：`, write error `本地TTS注册表保存失败：`)
//   * import (0xfe6058): the package job runs in a background isolate (`zipPath`, `tmpPath` = `.importing`, `finalRoot`,
//     `existingNames`); failure → `本地TTS导入失败：…` in the log and the job's message to the caller (`导入失败` when it has none)
//   * synthesize (0xe962d4 → 0xe96428, under `_synthLock`): `本地模型不存在：<name>`, the engine config (0x20f028), for zipvoice the
//     reference WAV from the page's data URI (`克隆引擎缺少参考音频`), message to the worker with `numThreads` (model setting or
//     [defaultThreads], 0x200da8) and `numSteps` (model setting or 4); result is the worker's WAV, `本地合成为空` when it has no
//     samples; errors other than `已取消` / `内存超限冷却中` are logged as `本地TTS合成失败（<model>）：…`
//   * watchdogs: no progress for 180 s → `本地TTS合成超时（180s 无任何进展），强杀 worker 重建`, the request fails with `本地合成超时`
//     (0x2007f8 / 0x200d60); destroy waits 10 s, then `本地TTS销毁超时（10s），强杀 worker` / `本地销毁超时` (0x2007bc); 20 s idle in
//     the background → `本地TTS：后台空闲 20 秒，销毁实例释放内存` (0x2bf950); a recycled instance or a system memory warning
//     (`_MemoryPressureGuard`) starts a cool-down during which synthesis fails with `内存超限冷却中`; worker events are logged as
//     `本地TTS：检测到内存风险，回收实例（<reason>）` and `本地TTS：rss=<n>MB，实例增长=<n>MB` (0x20e250).
// TODO(asm 0xe96f68): the original's memory threshold for recycling is not decoded; [maxGrowthMb] is a guess.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../../common/app_dirs.dart';
import 'local_tts_files.dart';
import 'local_tts_model.dart';
import 'local_tts_worker.dart';
import 'sherpa_synthesizer.dart';

export 'local_tts_files.dart' show LocalTtsError;
export 'local_tts_model.dart';

/// What the TTS dispatcher needs from the local engine; tests and the reader can swap [instance].
abstract class LocalTtsEngine {
  static LocalTtsEngine instance = const LocalTtsEngineDefault();

  /// WAV bytes of [text] spoken by voice [voiceId] of the model [model]; zipvoice models clone the voice of
  /// [referenceAudioDataUri] (`data:audio/wav;base64,…`) whose words are [referenceText].
  Future<Uint8List> synthesize(String model, int voiceId, String text, {String referenceAudioDataUri = '', String referenceText = ''});
}

/// The engine of the app: [LocalTtsManager] and its worker.
class LocalTtsEngineDefault implements LocalTtsEngine {
  const LocalTtsEngineDefault();
  @override
  Future<Uint8List> synthesize(String model, int voiceId, String text, {String referenceAudioDataUri = '', String referenceText = ''}) =>
      LocalTtsManager.synthesize(model, voiceId, text, referenceAudioDataUri: referenceAudioDataUri, referenceText: referenceText);
}

/// A finished import: the registered model and the size of its folder.
class LocalTtsImported {
  final LocalTtsModel model;
  final int bytes;
  const LocalTtsImported(this.model, this.bytes);
  double get megabytes => bytes / (1024 * 1024);
}

/// A tiny async mutex (the original uses `synchronized`'s Lock).
class _Lock {
  Future<void> _last = Future<void>.value();
  Future<T> run<T>(Future<T> Function() f) {
    final prev = _last;
    final done = Completer<void>();
    _last = done.future;
    return prev.then((_) => f()).whenComplete(done.complete);
  }
}

abstract class LocalTtsManager {
  // ---------------------------------------------------------------- configuration (tests shorten the timeouts)

  /// Makes the engine inside the worker; tests install a fake (must be a top-level / static function).
  static LocalSynthesizerFactory synthesizerFactory = createSherpaSynthesizer;
  static Duration watchdogTimeout = const Duration(seconds: 180);
  static Duration destroyTimeout = const Duration(seconds: 10);
  static Duration backgroundIdle = const Duration(seconds: 20);
  static Duration memoryCooldown = const Duration(seconds: 30);
  static int maxGrowthMb = 1500;

  /// Where the messages of the original's debugPrint calls go.
  static void Function(String message) log = (m) => debugPrint(m);

  /// Physical RAM in MB (iOS, from device_info_plus; static 0x1cbc of the original), null until probed.
  static int? physicalRamMb;

  // ---------------------------------------------------------------- state

  static final _Lock _lock = _Lock();
  static final _Lock _synthLock = _Lock();
  static List<LocalTtsModel> _models = [];
  static bool _loaded = false;

  static Isolate? _isolate;
  static SendPort? _send;
  static ReceivePort? _rx;
  static Future<SendPort>? _starting;
  static final Map<int, Completer<Uint8List?>> _pending = {};
  static final Map<int, Timer> _watchdogs = {};
  static int _nextId = 0;
  static int _epoch = 0;
  static DateTime? _coolUntil;
  static bool _background = false;
  static Timer? _idle;
  static _MemoryPressureGuard? _guard;

  /// Called for each progress event of the request in flight (UI spinners).
  static void Function(double progress)? onProgress;

  // ---------------------------------------------------------------- paths

  static Directory get root => AppDirs.dir(LocalTtsFiles.rootName);
  static Directory get sharedDir => Directory(p.join(root.path, LocalTtsFiles.sharedName));
  static File get _registry => File(p.join(root.path, LocalTtsFiles.registryName));
  static Directory dirOf(String name) => Directory(p.join(root.path, name));

  // ---------------------------------------------------------------- registry

  static List<LocalTtsModel> get models => List.unmodifiable(_models);
  static bool get loaded => _loaded;

  static LocalTtsModel? byName(String name) {
    for (final m in _models) {
      if (m.name == name) return m;
    }
    return null;
  }

  static Future<List<LocalTtsModel>> load({bool force = false}) => _lock.run(() async {
        if (!_loaded || force) {
          _models = _read();
          _loaded = true;
        }
        return models;
      });

  static List<LocalTtsModel> _read() {
    final f = _registry;
    if (!f.existsSync()) return [];
    try {
      final v = jsonDecode(f.readAsStringSync());
      return [
        if (v is List)
          for (final e in v)
            if (e is Map) LocalTtsModel.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (e) {
      log('本地TTS注册表读取失败：$e');
      return [];
    }
  }

  static Future<void> _save() async {
    try {
      final f = _registry;
      if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert([for (final m in _models) m.toJson()]), flush: true);
    } catch (e) {
      log('本地TTS注册表保存失败：$e');
    }
  }

  /// Imports a model package (`.zip` like the original; release `.tar.bz2` archives too). Throws [LocalTtsError] with the
  /// original's message.
  static Future<LocalTtsImported> importZip(String path) => _lock.run(() async {
        if (!_loaded) {
          _models = _read();
          _loaded = true;
        }
        final req = <String, Object?>{
          'zipPath': path,
          'tmpPath': p.join(root.path, LocalTtsFiles.importingName),
          'finalRoot': root.path,
          'existingNames': [for (final m in _models) m.name],
          'sharedDir': sharedDir.path,
        };
        final r = await _runImport(req);
        if (r['success'] != true) {
          final err = '${r['error'] ?? ''}'.trim();
          log('本地TTS导入失败：$err');
          throw LocalTtsError(err.isEmpty ? '导入失败' : err);
        }
        final model = LocalTtsModel(
          name: '${r['name']}',
          type: r['type'] is int ? r['type'] as int : 0,
          engine: '${r['engine']}',
          voices: [
            for (final v in (r['voices'] as List?) ?? const [])
              if (v is Map) LocalTtsVoice.fromJson(Map<String, dynamic>.from(v)),
          ],
          importTime: DateTime.now().millisecondsSinceEpoch,
        );
        _models
          ..removeWhere((m) => m.name == model.name)
          ..add(model);
        await _save();
        return LocalTtsImported(model, r['size'] is int ? r['size'] as int : 0);
      });

  // the closure sent to the isolate captures nothing but the request
  static Future<Map<String, Object?>> _runImport(Map<String, Object?> req) => Isolate.run(() => LocalTtsFiles.importPackage(req));

  /// Installs a standalone vocos vocoder (`*vocos*.onnx`) into `_shared` for packages that ship without one (replica).
  /// Returns its file name.
  static Future<String> importShared(String path) => _lock.run(() async {
        if (!LocalTtsFiles.isVocoderFile(path)) throw const LocalTtsError('模型不正确');
        final d = sharedDir;
        if (!d.existsSync()) d.createSync(recursive: true);
        final name = p.basename(path);
        await File(path).copy(p.join(d.path, name));
        return name;
      });

  /// Removes a model and its folder; the engines made from it stay (`删除模型会保留由它生成的全部朗读引擎。`).
  static Future<void> delete(String name) async {
    if (_send != null) await destroy();
    await _lock.run(() async {
      _models.removeWhere((m) => m.name == name);
      await _save();
      final d = dirOf(name);
      if (LocalTtsFiles.validName(name) && d.existsSync()) await d.delete(recursive: true);
    });
  }

  /// Thread count of a model (null = platform default); the worker re-creates the instance on the next request.
  static Future<void> setNumThreads(String name, int? n) => _update(name, (m) => m.numThreads = n);

  /// Flow-matching steps of a zipvoice model (null = 4).
  static Future<void> setNumSteps(String name, int? n) => _update(name, (m) => m.numSteps = n);

  static Future<void> _update(String name, void Function(LocalTtsModel m) f) => _lock.run(() async {
        final m = byName(name);
        if (m == null) throw LocalTtsError('本地模型不存在：$name');
        f(m);
        await _save();
      });

  /// Upper bound of the thread setting (`线程数必须在 1 ~ n 之间`).
  static int get maxThreads => Platform.numberOfProcessors < 1 ? 1 : Platform.numberOfProcessors;

  /// The platform default thread count (0x200da8): iOS by RAM (< 5500 MB → 1, < 7500 MB → 2, else 3); elsewhere half the cores
  /// clamped to 4..16, and to 2..4 on devices with less than 8 GB.
  static int defaultThreads({bool? ios, int? ramMb, int? cores}) {
    final ram = ramMb ?? physicalRamMb ?? 0;
    if (ios ?? Platform.isIOS) return ram < 5500 ? 1 : (ram < 7500 ? 2 : 3);
    var n = ((cores ?? Platform.numberOfProcessors) ~/ 2).clamp(4, 16);
    if (ram > 0 && ram < 8192) n = n.clamp(2, 4);
    return n;
  }

  static Future<void> _probeDevice() async {
    if (physicalRamMb != null || !Platform.isIOS) return;
    try {
      physicalRamMb = (await DeviceInfoPlugin().iosInfo).physicalRamSize;
    } catch (_) {
      physicalRamMb = 0;
    }
  }

  // ---------------------------------------------------------------- synthesis

  /// WAV bytes of [text] (see [LocalTtsEngine.synthesize]). One request at a time.
  static Future<Uint8List> synthesize(String modelName, int voiceId, String text,
          {String referenceAudioDataUri = '', String referenceText = ''}) =>
      _synthLock.run(() => _synthesize(modelName, voiceId, text, referenceAudioDataUri, referenceText));

  static Future<Uint8List> _synthesize(String name, int voiceId, String text, String refUri, String refText) async {
    if (!_loaded) await load();
    final model = byName(name);
    if (model == null) throw LocalTtsError('本地模型不存在：$name');
    try {
      final cfg = LocalTtsFiles.modelConfig(dirOf(name), model.engine, sharedDir: sharedDir.path);
      Float32List? ref;
      var refRate = 0;
      if (model.isClone) {
        final bytes = LocalTtsFiles.dataUriBytes(refUri);
        if (bytes.isEmpty) throw const LocalTtsError('克隆引擎缺少参考音频');
        final w = LocalTtsFiles.readWav(bytes);
        ref = w.samples;
        refRate = w.sampleRate;
      }
      final cool = _coolUntil;
      if (cool != null && DateTime.now().isBefore(cool)) throw const LocalTtsError('内存超限冷却中');
      _installGuard();
      await _probeDevice();
      final port = await _worker();
      final id = ++_nextId;
      final c = Completer<Uint8List?>();
      _pending[id] = c;
      _arm(id);
      port.send({
        'cmd': 'synthesize',
        'id': id,
        'voiceId': voiceId,
        'text': text,
        'epoch': _epoch,
        'config': cfg,
        'numThreads': model.numThreads ?? defaultThreads(),
        'numSteps': model.numSteps ?? 4,
        'background': _background,
        if (ref != null) 'refAudio': TransferableTypedData.fromList([ref.buffer.asUint8List(ref.offsetInBytes, ref.lengthInBytes)]),
        'refSampleRate': refRate,
        'refText': refText,
      });
      final wav = await c.future;
      if (wav == null || wav.length <= 44) throw const LocalTtsError('本地合成为空');
      return wav;
    } catch (e) {
      final s = '$e';
      if (s != '已取消' && s != '内存超限冷却中') log('本地TTS合成失败（$name）：$s');
      rethrow;
    } finally {
      if (_background) _armIdle();
    }
  }

  /// Fails the requests in flight with `已取消` and makes the worker drop the queued ones.
  static void cancel() {
    final old = _epoch++;
    _send?.send({'cmd': 'cancel', 'epoch': old});
    _failAll('已取消');
  }

  /// Frees the engine instance (memory); the worker stays. Kills the worker when it does not answer within [destroyTimeout].
  static Future<void> destroy() async {
    final port = _send;
    if (port == null) return;
    final id = ++_nextId;
    final c = Completer<Uint8List?>();
    _pending[id] = c;
    port.send({'cmd': 'destroy', 'id': id});
    try {
      await c.future.timeout(destroyTimeout, onTimeout: () {
        log('本地TTS销毁超时（10s），强杀 worker');
        _kill();
        _failAll('本地销毁超时');
        throw const LocalTtsError('本地销毁超时');
      });
    } catch (e) {
      log('本地TTS销毁实例失败：$e');
    } finally {
      _pending.remove(id);
    }
  }

  /// Whether a worker isolate is running (tests).
  static bool get workerRunning => _send != null;

  /// Requests waiting for the worker (tests).
  static int get pendingCount => _pending.length;

  /// Feeds a worker message to the main-side handler (tests).
  @visibleForTesting
  static void debugWorkerMessage(Map<String, Object?> m) => _onMessage(m);

  /// Stops everything and forgets the registry in memory (tests, sign-out).
  static Future<void> reset() async {
    _kill();
    _failAll('已取消');
    _idle?.cancel();
    _idle = null;
    _coolUntil = null;
    _background = false;
    _models = [];
    _loaded = false;
    onProgress = null;
  }

  // ---------------------------------------------------------------- app state (`_MemoryPressureGuard`)

  /// App lifecycle: in the background the worker throttles and the instance is freed after [backgroundIdle] without requests.
  static void lifecycle(AppLifecycleState s) {
    _background = s != AppLifecycleState.resumed;
    _idle?.cancel();
    _idle = null;
    if (_background) _armIdle();
  }

  /// A system memory warning: free the instance and cool down.
  static void memoryPressure() {
    if (_send == null) return;
    log('本地TTS：检测到内存风险，回收实例（系统内存警告）');
    _coolUntil = DateTime.now().add(memoryCooldown);
    destroy();
  }

  static void _armIdle() {
    _idle?.cancel();
    _idle = Timer(backgroundIdle, () {
      _idle = null;
      if (!_background || _send == null || _pending.isNotEmpty) return;
      log('本地TTS：后台空闲 20 秒，销毁实例释放内存');
      destroy();
    });
  }

  static void _installGuard() {
    if (_guard != null) return;
    try {
      final g = _MemoryPressureGuard();
      WidgetsBinding.instance.addObserver(g);
      _guard = g;
    } catch (_) {}
  }

  // ---------------------------------------------------------------- worker

  static Future<SendPort> _worker() {
    final s = _send;
    if (s != null) return Future.value(s);
    return _starting ??= _spawn().whenComplete(() => _starting = null);
  }

  static Future<SendPort> _spawn() async {
    final rx = ReceivePort();
    _rx = rx;
    final first = Completer<SendPort>();
    rx.listen((m) {
      if (m is SendPort) {
        if (!first.isCompleted) first.complete(m);
      } else if (m == null) {
        // onExit: the worker died (native crash, kill)
        if (identical(_rx, rx)) {
          _send = null;
          _isolate = null;
          _failAll('本地合成失败');
        }
        if (!first.isCompleted) first.completeError(const LocalTtsError('本地合成失败'));
      } else if (m is List) {
        log('本地TTS worker 错误：${m.isNotEmpty ? m.first : m}');
      } else {
        _onMessage(m);
      }
    });
    try {
      _isolate = await Isolate.spawn<List<Object?>>(
        LocalTtsWorker.main,
        [rx.sendPort, synthesizerFactory, {'maxGrowthMb': maxGrowthMb, 'ios': Platform.isIOS}],
        onExit: rx.sendPort,
        onError: rx.sendPort,
        errorsAreFatal: false,
      );
      final port = await first.future.timeout(const Duration(seconds: 20));
      _send = port;
      return port;
    } catch (e) {
      rx.close();
      if (identical(_rx, rx)) _rx = null;
      rethrow;
    }
  }

  /// Messages of the worker (0x20e250).
  static void _onMessage(Object? m) {
    if (m is! Map) return;
    final event = m['event'];
    if (event == 'recycled') {
      log('本地TTS：检测到内存风险，回收实例（${m['reason'] ?? '未知原因'}）');
      _coolUntil = DateTime.now().add(memoryCooldown);
      return;
    }
    if (event == 'rss') {
      log('本地TTS：rss=${m['rss']}MB，实例增长=${m['delta']}MB');
      return;
    }
    final id = m['id'];
    if (id is! int) return;
    if (event == 'progress') {
      if (_pending.containsKey(id)) {
        _arm(id);
        final pr = m['progress'];
        onProgress?.call(pr is num ? pr.toDouble() : 0);
      }
      return;
    }
    _watchdogs.remove(id)?.cancel();
    final c = _pending.remove(id);
    if (c == null || c.isCompleted) return;
    if (m['ok'] == true) {
      final w = m['wav'];
      c.complete(w is TransferableTypedData ? w.materialize().asUint8List() : null);
    } else {
      c.completeError(LocalTtsError('${m['error'] ?? '本地合成失败'}'));
    }
  }

  static void _arm(int id) {
    _watchdogs.remove(id)?.cancel();
    _watchdogs[id] = Timer(watchdogTimeout, () => _onWatchdogFire(id));
  }

  static void _onWatchdogFire(int id) {
    _watchdogs.remove(id);
    if (!_pending.containsKey(id)) return;
    log('本地TTS合成超时（180s 无任何进展），强杀 worker 重建');
    _kill();
    _failAll('本地合成超时');
  }

  static void _failAll(String message) {
    for (final t in _watchdogs.values) {
      t.cancel();
    }
    _watchdogs.clear();
    final all = Map.of(_pending);
    _pending.clear();
    for (final c in all.values) {
      if (!c.isCompleted) c.completeError(LocalTtsError(message));
    }
  }

  static void _kill() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _send = null;
    _rx?.close();
    _rx = null;
    _epoch++;
  }
}

/// `_MemoryPressureGuard` (class id 5658): forwards memory warnings and lifecycle changes to the manager.
class _MemoryPressureGuard extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() => LocalTtsManager.memoryPressure();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => LocalTtsManager.lifecycle(state);
}
