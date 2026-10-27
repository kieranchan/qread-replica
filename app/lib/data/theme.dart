// data/theme.dart — the installed UI themes (主题). File-store key `themes` (JSON list of [ThemeModel], see docs/SETTINGS.md
// "themes: theme list (file store)"); `ThemeManager.themes` is static 0x4ac8 in the original. The theme plaza / download / apply
// logic lives in the theme pages (`pages/theme/`); this is only the installed list.
import '../models/theme.dart';
import 'list_store.dart';

abstract class ThemeManager {
  static final ListStore<ThemeModel> store = ListStore<ThemeModel>(
    'themes',
    fromJson: ThemeModel.fromJson,
    toJson: (t) => t.toJson(),
    label: '主题',
  );

  static List<ThemeModel> get themes => store.items;

  static Future<List<ThemeModel>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static ThemeModel? byId(String id) {
    for (final t in store.items) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Installs a theme; a theme with the same id is replaced in place (an update of the same theme).
  static Future<void> install(ThemeModel theme) => store.run((list) {
        final copy = ThemeModel.fromJson(theme.toJson());
        final i = list.indexWhere((e) => e.id == copy.id);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> remove(String id) => store.run((list) => list.removeWhere((e) => e.id == id));
}
