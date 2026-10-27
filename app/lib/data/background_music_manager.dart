// data/background_music_manager.dart — reading background music: files the user picked, kept in `<root>/background_music/`.
// File-store key `backgroundMusic` (JSON list of [BackgroundMusic] {id, name, path}); the volume is the prefs double
// `backgroundMusicVolume` (0.1 .. 0.8, default 0.1); the selected track id is `backgroundMusicSelected` (replica key).
//
// Original: `BackgroundMusicManager` (`_musics` 0x4138, `_lock` 0x4128; load 0x10db0f8, save 0x1092cf4 prints `背景音乐保存失败…`).
// The playback itself (`util/audio`) is not here.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../models/background_music.dart';
import '../storage/storage.dart';
import 'list_store.dart';

abstract class BackgroundMusicManager {
  static const String volumeKey = 'backgroundMusicVolume';
  static const String selectedKey = 'backgroundMusicSelected';
  static const double minVolume = 0.1;
  static const double maxVolume = 0.8;

  static final ListStore<BackgroundMusic> store = ListStore<BackgroundMusic>(
    'backgroundMusic',
    fromJson: BackgroundMusic.fromJson,
    toJson: (m) => m.toJson(),
    label: '背景音乐',
  );

  static List<BackgroundMusic> get musics => store.items;

  static Future<List<BackgroundMusic>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static Directory get directory => AppDirs.dir('background_music');

  /// The absolute path of a track's file (`path` may be a bare file name inside [directory]).
  static String filePath(BackgroundMusic m) => p.isAbsolute(m.path) ? m.path : p.join(directory.path, m.path);

  /// Copies [source] into the music folder and registers it (name defaults to the file name without extension).
  static Future<BackgroundMusic> add(File source, {String? name}) async {
    await AppDirs.ensure('background_music');
    final id = newId();
    final fileName = '$id${p.extension(source.path)}';
    await source.copy(p.join(directory.path, fileName));
    final m = BackgroundMusic(id: id, name: name ?? p.basenameWithoutExtension(source.path), path: fileName);
    await store.run((list) => list.add(m));
    return m;
  }

  /// Removes the track and its file; clears the selection when it was selected.
  static Future<void> remove(String id) async {
    await store.run((list) async {
      final i = list.indexWhere((e) => e.id == id);
      if (i < 0) return;
      final m = list.removeAt(i);
      final f = File(filePath(m));
      if (f.existsSync()) await f.delete();
    });
    if (selectedId == id) await Storage.remove(selectedKey);
  }

  static Future<void> rename(String id, String name) => store.run((list) {
        for (final e in list) {
          if (e.id == id) e.name = name;
        }
      });

  static String get selectedId => Storage.getString(selectedKey);

  static BackgroundMusic? get selected {
    final id = selectedId;
    for (final m in store.items) {
      if (m.id == id) return m;
    }
    return null;
  }

  static Future<void> select(String id) => Storage.setString(selectedKey, id);

  /// Volume clamped to 0.1 .. 0.8.
  static double get volume => Storage.getDouble(volumeKey, minVolume).clamp(minVolume, maxVolume).toDouble();

  static Future<void> setVolume(double v) => Storage.setDouble(volumeKey, v.clamp(minVolume, maxVolume).toDouble());
}
