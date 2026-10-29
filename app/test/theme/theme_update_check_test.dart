// Start-up theme update notice (pages/theme/theme_update_check.dart): only plaza themes are checked, a different plaza version is
// reported, errors never surface as a notice.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/theme.dart';
import 'package:newread/pages/theme/theme_api.dart';
import 'package:newread/pages/theme/theme_update_check.dart';

void main() {
  final asked = <int>[];
  setUp(() {
    asked.clear();
    ThemeUpdateCheck.fetch = (id) async {
      asked.add(id);
      if (id == 404) throw ThemeApiException('not found');
      return PlazaTheme(id: id, name: 'T$id', version: id == 7 ? '1.1.0' : '1.0.0');
    };
  });

  test('plaza id from the installed id', () {
    expect(ThemeUpdateCheck.plazaId(ThemeModel(id: 'plaza_12')), 12);
    expect(ThemeUpdateCheck.plazaId(ThemeModel(id: 'mine')), isNull);
    expect(ThemeUpdateCheck.plazaId(ThemeModel(id: 'plaza_x')), isNull);
  });

  test('check: newer version of a plaza theme, nothing for own themes or an up-to-date one', () async {
    expect(await ThemeUpdateCheck.check(theme: ThemeModel(id: 'plaza_7', version: '1.0.0')), '1.1.0');
    expect(await ThemeUpdateCheck.check(theme: ThemeModel(id: 'plaza_8', version: '1.0.0')), isNull);
    expect(await ThemeUpdateCheck.check(theme: ThemeModel(id: 'custom', version: '1.0.0')), isNull);
    expect(asked, [7, 8]);
    expect(ThemeUpdateCheck.check(theme: ThemeModel(id: 'plaza_404', version: '1')), throwsA(isA<ThemeApiException>()));
  });
}
