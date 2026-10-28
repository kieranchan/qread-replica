// util/audio/local/sherpa_synthesizer.dart — the real engine of the worker: sherpa-onnx `OfflineTts` (package sherpa_onnx 1.13.8, the
// original's version), configured as the original worker does (0xe96f68): provider `cpu`, debug off, the model family from the
// package's `engine`, OfflineTtsConfig(maxNumSentences: 1, ruleFars: '', silenceScale: 0.2), generation with speed 1.0 and
// silenceScale 0.2; zipvoice gets the reference samples / sample rate / text and `numSteps`.
// Only the worker isolate touches this file at run time (each isolate binds the native library itself: `initBindings()`); on iOS
// the library is linked into the app (sherpa_onnx_ios xcframework), so `DynamicLibrary.process()` finds it.
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'local_tts_files.dart';
import 'local_tts_worker.dart';

/// The default [LocalSynthesizerFactory] (top-level so it can be sent to the worker).
LocalSynthesizer createSherpaSynthesizer(Map<String, String> config, int numThreads) => SherpaSynthesizer(config, numThreads);

class SherpaSynthesizer implements LocalSynthesizer {
  static bool _bound = false;
  sherpa.OfflineTts? _tts;

  SherpaSynthesizer(Map<String, String> c, int numThreads) {
    if (!_bound) {
      sherpa.initBindings();
      _bound = true;
    }
    String s(String k) => c[k] ?? '';
    final threads = numThreads < 1 ? 1 : numThreads;
    final sherpa.OfflineTtsModelConfig model;
    switch (s('engine')) {
      case 'matcha':
        model = sherpa.OfflineTtsModelConfig(
          matcha: sherpa.OfflineTtsMatchaModelConfig(
            acousticModel: s('model'),
            vocoder: s('vocoder'),
            lexicon: s('lexicon'),
            tokens: s('tokens'),
            dataDir: s('dataDir'),
            dictDir: s('dictDir'),
            noiseScale: 0.667,
            lengthScale: 1.0,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        );
      case 'zipvoice':
        model = sherpa.OfflineTtsModelConfig(
          zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
            tokens: s('tokens'),
            encoder: s('encoder'),
            decoder: s('decoder'),
            vocoder: s('vocoder'),
            dataDir: s('dataDir'),
            lexicon: s('lexicon'),
            featScale: 0.1,
            tShift: 0.5,
            targetRms: 0.1,
            guidanceScale: 1.0,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        );
      case 'vits':
        model = sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: s('model'),
            lexicon: s('lexicon'),
            tokens: s('tokens'),
            dataDir: s('dataDir'),
            dictDir: s('dictDir'),
            noiseScale: 0.4,
            noiseScaleW: 0.8,
            lengthScale: 1.0,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        );
      case 'kokoro':
        model = sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: s('model'),
            voices: s('voices'),
            tokens: s('tokens'),
            dataDir: s('dataDir'),
            dictDir: s('dictDir'),
            lexicon: s('lexicon'),
            lengthScale: 1.0,
          ),
          numThreads: threads,
          debug: false,
          provider: 'cpu',
        );
      default:
        throw LocalTtsError('模型不正确：${s('engine')}');
    }
    _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: model,
      ruleFsts: s('ruleFsts'),
      maxNumSenetences: 1,
      ruleFars: '',
      silenceScale: 0.2,
    ));
  }

  @override
  LocalGenerated generate({
    required String text,
    required int sid,
    Float32List? referenceAudio,
    int referenceSampleRate = 0,
    String referenceText = '',
    int numSteps = 5,
    int Function(Float32List samples, double progress)? onProgress,
  }) {
    final t = _tts;
    if (t == null) throw const LocalTtsError('本地合成失败');
    final a = t.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(
        silenceScale: 0.2,
        speed: 1.0,
        sid: sid,
        referenceAudio: referenceAudio,
        referenceSampleRate: referenceSampleRate,
        referenceText: referenceText,
        numSteps: numSteps,
      ),
      onProgress: onProgress,
    );
    return LocalGenerated(a.samples, a.sampleRate);
  }

  @override
  void free() {
    _tts?.free();
    _tts = null;
  }
}
