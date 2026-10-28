import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/webbook/model/book_source.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

void main() {
  setUp(() {
    JsEngines.useDart();
    CacheManager.resetForTests();
  });

  test('explore kinds: Legado type names; actions run with key / value and the input is kept with source.put', () async {
    final src = BookSource.fromJson({
      'bookSourceUrl': 'https://e.test',
      'bookSourceName': 'E',
      'exploreUrl': jsonEncode([
        {'title': '榜单', 'url': '/rank/{{page}}'},
        {'title': '分类', 'type': 'title'},
        {'title': '关键词', 'type': 'text', 'action': '"/s?k=" + value'},
        {'title': '刷新', 'type': 'button', 'action': '"/r?k=" + source.get("关键词")'},
        {'title': '性别', 'type': 'select', 'chars': ['男', '女'], 'action': '"/g/" + value'},
        {'title': '开关', 'type': 'toggle', 'chars': ['开', '关']},
      ]),
    });
    final kinds = await SourceApi.exploreKinds(src);
    expect(kinds.map((k) => k.type), [ExploreKind.typeUrl, ExploreKind.typeTitle, ExploreKind.typeText, ExploreKind.typeButton,
      ExploreKind.typeSelect, ExploreKind.typeToggle]);
    expect(kinds.map((k) => k.toExplore().type_), [0, 1, 3, 2, 4, 5]);
    expect(await SourceApi.exploreAction(src, kinds[2].action, key: '关键词', value: '玄幻'), '/s?k=玄幻');
    expect(await SourceApi.exploreAction(src, kinds[3].action, key: '刷新'), '/r?k=玄幻');
    expect(await SourceApi.exploreAction(src, kinds[4].action, key: '性别', value: '女'), '/g/女');
    expect(await SourceApi.exploreAction(src, 'undefined', key: '开关', value: '关'), '');
    expect(src.get('开关'), '关');
  });
}
