// 添加配置: the imported text goes to the list its fields belong to.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/init/glue_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('qread_cfg_');
    SharedPreferences.setMockInitialValues({});
    await AppInit.init(prefs: await SharedPreferences.getInstance(), root: root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('replace rules, TXT rules and book sources are recognised', () async {
    final replaces = ReplaceData.rules.length;
    expect(await GlueRoutes.importText(jsonEncode([{'name': '去广告', 'pattern': '广告', 'replacement': '', 'isRegex': false}])), 1);
    expect(ReplaceData.rules.length, replaces + 1);

    final rules = Txtruledata.rules.length;
    expect(await GlueRoutes.importText(jsonEncode({'name': '第X章', 'rule': r'^第.+章'})), 1);
    expect(Txtruledata.rules.length, rules + 1);

    expect(await GlueRoutes.importText(jsonEncode([{'bookSourceUrl': 'http://example.invalid', 'bookSourceName': '例子'}])), 1);
    expect(Sourcedata.byUrl('http://example.invalid'), isNotNull);

    expect(() => GlueRoutes.importText('{"hello": 1}'), throwsFormatException);
  });
}
