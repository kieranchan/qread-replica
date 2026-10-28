// util/audio/local/local_tts_worker.dart — the synthesis worker isolate of the original LocalTtsManager (`_workerMain` 0x2010a8, body
// 0xe96f68). The main isolate (local_tts_manager.dart) talks to it with maps:
//   main → worker  {cmd: synthesize, id, epoch, config{engine, model, encoder, decoder, vocoder, lexicon, tokens, dataDir, ruleFsts,
//                    dictDir, voices}, voiceId, text, numThreads, numSteps, background, refAudio (TransferableTypedData of float32
//                    samples), refSampleRate, refText}
//                  {cmd: cancel, epoch}  — requests sent with an epoch ≤ this one are answered `已取消`
//                  {cmd: destroy, id}    — frees the engine instance, answers {id, ok: true}
//   worker → main  its SendPort first, then {id, ok: true, wav} | {id, ok: false, error}
//                  {event: progress, id} (each engine callback; the main side resets that request's 180 s watchdog)
//                  {event: rss, rss, delta} (MB of the process and of the growth since the instance was created)
//                  {event: recycled, reason} (instance freed because it grew past the limit)
// One engine instance is kept and re-created when the model or the thread count changes. Engine settings as the original
// (OfflineTtsConfig maxNumSentences 1, silenceScale 0.2; generation speed 1.0, silenceScale 0.2, numSteps default 5; matcha
// noiseScale 0.667; vits noiseScale 0.4 / noiseScaleW 0.8; zipvoice featScale 0.1, tShift 0.5, targetRms 0.1, guidanceScale 1.0;
// provider cpu) live in sherpa_synthesizer.dart. In the background on iOS the progress callback sleeps 0.75 × the time since the
// previous callback (200..2000 ms, progressCb 0x20dfa0) to stay under iOS's background CPU limit.
//
// The engine is a [LocalSynthesizer] made by the factory passed at spawn time, so tests run the real protocol with a fake engine
// and never load the native library.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'local_tts_files.dart';

class LocalGenerated {
  final Float32List samples;
  final int sampleRate;
  const LocalGenerated(this.samples, this.sampleRate);
}

/// One loaded model (sherpa-onnx `OfflineTts`, or a fake in tests). Lives inside the worker isolate.
abstract class LocalSynthesizer {
  /// Synthesizes [text]; [onProgress] is called with partial samples and 0..1 progress and returns 1 to continue, 0 to stop.
  LocalGenerated generate({
    required String text,
    required int sid,
    Float32List? referenceAudio,
    int referenceSampleRate = 0,
    String referenceText = '',
    int numSteps = 5,
    int Function(Float32List samples, double progress)? onProgress,
  });

  void free();
}

/// Makes the engine for a model config (see [LocalTtsFiles.modelConfig]) and a thread count. Must be a top-level or static function:
/// it is sent to the worker isolate.
typedef LocalSynthesizerFactory = LocalSynthesizer Function(Map<String, String> config, int numThreads);

abstract class LocalTtsWorker {
  /// Isolate entry point: [args] = [SendPort toMain, LocalSynthesizerFactory factory, Map options]. Options: `maxGrowthMb` (recycle
  /// the instance when the process grew more than this since it was created; 0 = never), `ios` (throttle in the background).
  static Future<void> main(List<Object?> args) async {
    final toMain = args[0] as SendPort;
    final factory = args[1] as LocalSynthesizerFactory;
    final opts = args.length > 2 && args[2] is Map ? args[2] as Map : const {};
    final maxGrowthMb = opts['maxGrowthMb'] is int ? opts['maxGrowthMb'] as int : 0;
    final ios = opts['ios'] is bool ? opts['ios'] as bool : Platform.isIOS;
    final rx = ReceivePort();
    toMain.send(rx.sendPort);

    LocalSynthesizer? tts;
    var key = '';
    var base = 0;
    var cancelled = -1;
    void free() {
      try {
        tts?.free();
      } catch (_) {}
      tts = null;
      key = '';
    }

    await for (final m in rx) {
      if (m is! Map) continue;
      final id = m['id'];
      switch (m['cmd']) {
        case 'cancel':
          cancelled = math.max(cancelled, m['epoch'] is int ? m['epoch'] as int : 0);
          continue;
        case 'destroy':
          free();
          toMain.send({'id': id, 'ok': true});
          continue;
        case 'exit':
          free();
          rx.close();
          continue;
        case 'synthesize':
          break;
        default:
          continue;
      }
      final epoch = m['epoch'] is int ? m['epoch'] as int : 0;
      if (epoch <= cancelled) {
        toMain.send({'id': id, 'ok': false, 'error': '已取消'});
        continue;
      }
      try {
        final cfg = <String, String>{for (final e in (m['config'] as Map).entries) '${e.key}': '${e.value ?? ''}'};
        final threads = m['numThreads'] is int ? m['numThreads'] as int : 4;
        final k = '${cfg.entries.map((e) => '${e.key}=${e.value}').join(';')}|$threads';
        if (tts == null || key != k) {
          free();
          base = _rss();
          tts = factory(cfg, threads);
          key = k;
        }
        final clone = cfg['engine'] == 'zipvoice';
        Float32List? ref;
        final ra = m['refAudio'];
        if (ra is TransferableTypedData) {
          final b = ra.materialize();
          ref = b.asFloat32List(0, b.lengthInBytes ~/ 4);
        }
        if (clone && (ref == null || ref.isEmpty)) throw const LocalTtsError('克隆引擎缺少参考音频');
        final background = m['background'] == true;
        var last = DateTime.now();
        final out = tts!.generate(
          text: '${m['text'] ?? ''}',
          sid: m['voiceId'] is int ? m['voiceId'] as int : 0,
          referenceAudio: clone ? ref : null,
          referenceSampleRate: clone && m['refSampleRate'] is int ? m['refSampleRate'] as int : 0,
          referenceText: clone ? '${m['refText'] ?? ''}' : '',
          numSteps: m['numSteps'] is int ? m['numSteps'] as int : 5,
          onProgress: (samples, progress) {
            final now = DateTime.now();
            final spent = now.difference(last).inMilliseconds;
            last = now;
            toMain.send({'event': 'progress', 'id': id, 'progress': progress});
            if (background && ios) sleep(Duration(milliseconds: (spent * 0.75).round().clamp(200, 2000)));
            return 1;
          },
        );
        final wav = LocalTtsFiles.wavBytes(out.samples, out.sampleRate);
        toMain.send({'id': id, 'ok': true, 'wav': TransferableTypedData.fromList([wav])});
        final rss = _rss();
        final growth = (rss - base) >> 20;
        toMain.send({'event': 'rss', 'rss': rss >> 20, 'delta': growth});
        if (maxGrowthMb > 0 && growth > maxGrowthMb) {
          free();
          toMain.send({'event': 'recycled', 'reason': '实例增长 ${growth}MB'});
        }
      } catch (e) {
        toMain.send({'id': id, 'ok': false, 'error': '$e'});
      }
    }
  }

  static int _rss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}
