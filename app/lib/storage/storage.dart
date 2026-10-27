// Thin wrapper over SharedPreferences (static `Storage._prefs` in the original, offset 0x3da0).
import 'package:shared_preferences/shared_preferences.dart';

abstract class Storage {
  static late SharedPreferences _prefs;
  static bool _ready = false;

  static Future<void> init({SharedPreferences? prefs}) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _ready = true;
  }

  static bool get ready => _ready;

  static String getString(String key, [String def = '']) => _ready ? (_prefs.getString(key) ?? def) : def;
  static bool getBool(String key, [bool def = false]) => _ready ? (_prefs.getBool(key) ?? def) : def;
  static int getInt(String key, [int def = 0]) => _ready ? (_prefs.getInt(key) ?? def) : def;

  static Future<void> setString(String key, String value) async {
    if (_ready) await _prefs.setString(key, value);
  }

  static Future<void> setBool(String key, bool value) async {
    if (_ready) await _prefs.setBool(key, value);
  }

  static Future<void> setInt(String key, int value) async {
    if (_ready) await _prefs.setInt(key, value);
  }

  static Future<void> remove(String key) async {
    if (_ready) await _prefs.remove(key);
  }
}
