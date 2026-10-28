// Exploration tab: the active template's components load their books through the engine.
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
  test('ComponentType: the original order, found by name, anything else is 推荐卡片 (0x647e58 / 0x647e4c)', () {
    expect(ComponentType.values.map((t) => t.label), ['推荐卡片', '排行榜', '宫格', '左右滑动', '网络排行榜', '多分类排行榜', '错位瀑布流']);
    expect(ComponentType.values.map((t) => t.name),
        ['recommendCard', 'ranking', 'grid', 'horizontalScroll', 'networkRanking', 'multiCategoryRanking', 'staggeredWaterfall']);
    expect(ComponentType.of('ranking'), ComponentType.ranking);
    expect(ComponentType.of('staggeredWaterfall'), ComponentType.staggeredWaterfall);
    for (final v in ['ComponentType.grid', 6, '排行榜', null, '']) {
      expect(ComponentType.of(v), ComponentType.recommendCard, reason: '$v');
    }
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
