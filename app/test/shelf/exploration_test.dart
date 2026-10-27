// Exploration tab: the active template's components load their books through the engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/exploration.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/exploration_template.dart';
import 'package:newread/pages/exploration/exploration_page.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/widget/exploration/exploration_component.dart';

import 'support.dart';

void main() {
  test('ComponentType accepts names, labels and indexes', () {
    expect(ComponentType.of('ranking'), ComponentType.ranking);
    expect(ComponentType.of('ComponentType.grid'), ComponentType.grid);
    expect(ComponentType.of(6), ComponentType.staggeredWaterfall);
    expect(ComponentType.of('排行榜'), ComponentType.ranking);
  });

  testWidgets('a ranking component of the active template lists the explore books with ranks', (t) async {
    const src = 'http://src-a.test';
    final engine = FakeBookSearchService(pages: {
      '$src|/rank': [
        [for (var i = 0; i < 12; i++) Book(bookUrl: '$src/r/$i', name: '榜单书$i', author: '作者$i')],
      ],
    });
    late ShelfEnv env;
    await t.runAsync(() async {
      env = await shelfEnv(engine: engine);
      await Sources.add({'bookSourceUrl': src, 'bookSourceName': '源A', 'exploreUrl': '榜::/rank'});
      final tpl = await Exploration.create('默认', components: [
        ExplorationComponent(id: 'c1', type_: 'ranking', config: {'title': '热门榜', 'bookSourceUrl': src, 'exploreUrl': '/rank', 'count': 5}).toJson(),
      ]);
      await Exploration.setActive(tpl.id);
    });
    addTearDown(env.dispose);
    await t.pumpWidget(app(const ExplorationPage()));
    await settle(t);
    expect(find.text('热门榜'), findsOneWidget);
    expect(find.text('榜单书0'), findsWidgets);
    expect(find.text('榜单书4'), findsWidgets);
    expect(find.text('榜单书5'), findsNothing); // count 5
    expect(engine.calls, ['explore:/rank:1']);
  });

  // Second on purpose: the page reads the template store from the fake zone (see support.dart).
  testWidgets('empty exploration shows the original call to action', (t) async {
    final env = await pumpPage(t, const ExplorationPage());
    addTearDown(env.dispose);
    expect(find.text('发现更多精彩'), findsOneWidget);
    expect(find.text('开始创建'), findsOneWidget);
  });
}
