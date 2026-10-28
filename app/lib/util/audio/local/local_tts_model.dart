// util/audio/local/local_tts_model.dart — `LocalTtsModel` / `LocalTtsVoice` of the original ai/local_tts.dart (class ids 1665 / 1666):
// one imported sherpa-onnx model package and the voices its `tts.json` lists. The registry (`<documents>/local_tts/registry.json`)
// is a JSON list of [LocalTtsModel.toJson].
//
// Field order and JSON keys from the original (fromJson 0x215734 / toJson 0x215e90; voice fromJson 0x2161dc / toJson 0x2160b4):
//   LocalTtsModel {name, type:int, voices:[LocalTtsVoice], engine (default `kokoro`), importTime (ms), numThreads?, numSteps?}
//   LocalTtsVoice {id:int, name, lang, gender}
// `type` and `id` accept numbers or numeric strings (`int.tryParse`), the rest is read as text.

/// The engines a package can declare (`engine` of `tts.json`).
abstract class LocalTtsEngines {
  static const String matcha = 'matcha';
  static const String vits = 'vits';
  static const String kokoro = 'kokoro';

  /// The voice-cloning engine (`bdttsclone` pages): no preset voices, a reference WAV per engine.
  static const String zipvoice = 'zipvoice';

  static const List<String> all = [matcha, vits, kokoro, zipvoice];
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));

class LocalTtsVoice {
  int id;
  String name;
  String lang;
  String gender;

  LocalTtsVoice({this.id = 0, this.name = '', this.lang = '', this.gender = ''});

  factory LocalTtsVoice.fromJson(Map<String, dynamic> m) => LocalTtsVoice(
        id: _int(m['id']) ?? 0,
        name: '${m['name'] ?? ''}',
        lang: '${m['lang'] ?? ''}',
        gender: '${m['gender'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lang': lang, 'gender': gender};
}

class LocalTtsModel {
  String name;
  int type;
  List<LocalTtsVoice> voices;
  String engine;

  /// Milliseconds since epoch (`导入于 …`).
  int importTime;

  /// null = the platform default ([LocalTtsManager.defaultThreads]).
  int? numThreads;

  /// Flow-matching steps of zipvoice models; null = 4 (`默认（4 步）`).
  int? numSteps;

  LocalTtsModel({
    this.name = '',
    this.type = 0,
    List<LocalTtsVoice>? voices,
    this.engine = LocalTtsEngines.kokoro,
    this.importTime = 0,
    this.numThreads,
    this.numSteps,
  }) : voices = voices ?? [];

  factory LocalTtsModel.fromJson(Map<String, dynamic> m) {
    final v = m['voices'];
    final engine = '${m['engine'] ?? ''}'.trim();
    return LocalTtsModel(
      name: '${m['name'] ?? ''}',
      type: _int(m['type']) ?? 0,
      voices: [
        if (v is List)
          for (final e in v)
            if (e is Map) LocalTtsVoice.fromJson(Map<String, dynamic>.from(e)),
      ],
      engine: engine.isEmpty ? LocalTtsEngines.kokoro : engine,
      importTime: _int(m['importTime']) ?? 0,
      numThreads: _int(m['numThreads']),
      numSteps: _int(m['numSteps']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'voices': [for (final v in voices) v.toJson()],
        'engine': engine,
        'importTime': importTime,
        'numThreads': numThreads,
        'numSteps': numSteps,
      };

  /// zipvoice packages clone a voice from a reference WAV (`克隆模型 · 上传音频即可克隆音色`).
  bool get isClone => engine == LocalTtsEngines.zipvoice;

  LocalTtsVoice? voice(int id) {
    for (final v in voices) {
      if (v.id == id) return v;
    }
    return null;
  }
}
