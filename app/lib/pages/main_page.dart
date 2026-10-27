// pages/main_page.dart — the tab shell of the original (`_MainPageState`, 0x190 bytes): 书架 · 发现 · 探索 · 订阅 · 我的 by default
// (see [MainTabs]), tab icons and colours from the applied theme (ThemeProvider), and the start-up prompts of the original:
//   * privacy agreement on first launch (`privacy_agreement_agreed` = "true", dialog 0x8eb3b0, check 0x10bd05c)
//   * "continue reading" when the last reading ended less than 5 minutes ago (`last_open_time`, 0x10bdd44 / dialog 0x8eb8ec)
// Not ported: the update check (发现新版本: no update service for the replica), the 沉浸光感 effect picker (no shader effects),
// app links (`linkinit`) and the TTS shared-resource migration.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/common.dart';
import '../common/nav.dart';
import '../read/api/readapi.dart';
import '../storage/storage.dart';
import '../theme/theme_provider.dart';
import 'me_page.dart';

/// The tabs: page builders by tab name (set by `init/wiring.dart`), order and visibility as the original:
///  * order: prefs `bottomBarTabs`, a JSON list of tab names (read 0xf62c0c, written by the 底栏标签配置 sheet 0x101e764),
///    default 书架 发现 探索 订阅 我的;
///  * 发现 is shown when `toBool(getString("found") or "true")` (0x51391c: default on), 订阅 when `toBool(getString("ding"))`
///    (0x5138e0: no default, so it is hidden until switched on); 书架 and 我的 are always shown.
/// Whoever changes these prefs calls [changed] so the tab bar rebuilds.
class MainTabs {
  static const defaultOrder = ['书架', '发现', '探索', '订阅', '我的'];
  static const orderKey = 'bottomBarTabs';
  static const foundKey = 'found';
  static const dingKey = 'ding';
  static final Map<String, WidgetBuilder> builders = {};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void changed() => revision.value++;

  /// Every tab in the configured order (hidden ones included).
  static List<String> configured() {
    final raw = Storage.getString(orderKey);
    if (raw.isEmpty) return defaultOrder;
    try {
      final v = jsonDecode(raw);
      if (v is! List) return defaultOrder;
      final names = [for (final e in v) '$e'].where(defaultOrder.contains).toSet().toList();
      for (final n in defaultOrder) {
        if (!names.contains(n)) names.add(n);
      }
      return names;
    } catch (_) {
      return defaultOrder;
    }
  }

  static bool visible(String name) => switch (name) {
        '发现' => Storage.getBool(foundKey, true),
        '订阅' => Storage.getBool(dingKey, false),
        _ => true,
      };

  /// The tabs shown, in order.
  static List<String> order() => [for (final n in configured()) if (visible(n)) n];

  static Future<void> save(List<String> order, {required bool found, required bool ding}) async {
    await Storage.setString(orderKey, jsonEncode(order));
    await Storage.setBool(foundKey, found);
    await Storage.setBool(dingKey, ding);
    changed();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  /// `_MainPageState.showBottom` (static 0x968): pages hide the tab bar while they need the full screen.
  static final ValueNotifier<bool> showBottom = ValueNotifier<bool>(true);

  static const privacyKey = 'privacy_agreement_agreed';
  static const lastOpenKey = 'last_open_time';

  /// Marks "the user was reading just now" (the reader hook in wiring.dart stamps it when a book is closed).
  static Future<void> stampReading() => Storage.setInt(lastOpenKey, DateTime.now().millisecondsSinceEpoch);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<String> _tabs = MainTabs.order();

  /// Built tab pages by name (built on first visit, then kept alive).
  final Map<String, Widget> _pages = {};

  @override
  void initState() {
    super.initState();
    Common.index.addListener(_onIndex);
    MainTabs.revision.addListener(_onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    Common.index.removeListener(_onIndex);
    MainTabs.revision.removeListener(_onTabsChanged);
    super.dispose();
  }

  void _onIndex() {
    if (mounted) setState(() {});
  }

  /// The tab editor changed order / visibility: keep the current tab selected when it is still shown.
  void _onTabsChanged() {
    if (!mounted) return;
    final current = _tabs[Common.index.value.clamp(0, _tabs.length - 1)];
    setState(() {
      _tabs = MainTabs.order();
      final i = _tabs.indexOf(current);
      Common.index.value = i < 0 ? 0 : i;
    });
  }

  Future<void> _startup() async {
    if (!Storage.getBool(MainPage.privacyKey)) {
      await _privacy();
      if (!mounted) return;
    }
    await _continueReading();
  }

  Future<void> _privacy() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const Key('privacy_dialog'),
          title: const Text('隐私协议'),
          content: const SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('欢迎使用轻悦时光！', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              Text('在使用本应用前，请您仔细阅读并同意我们的隐私协议。'),
              SizedBox(height: 8),
              Text('我们非常重视您的个人信息和隐私保护。'),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // the original quits; iOS does not let an app quit itself, so the dialog simply stays
                if (Platform.isAndroid) SystemNavigator.pop();
              },
              child: const Text('不同意', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(onPressed: () => Nav.openNamed(ctx, 'user_ys'), child: const Text('查看协议')),
            TextButton(
              key: const Key('privacy_agree'),
              onPressed: () async {
                await Storage.setString(MainPage.privacyKey, 'true');
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('同意'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continueReading() async {
    final last = Storage.getInt(MainPage.lastOpenKey);
    if (last <= 0 || DateTime.now().millisecondsSinceEpoch - last > const Duration(minutes: 5).inMilliseconds) return;
    final history = await ReadApi.getHistory();
    if (history.isEmpty || !mounted) return;
    final book = history.first;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('继续阅读'),
        content: const Text('上次阅读距离现在不到5分钟，是否继续阅读上次的书籍？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('不')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('继续')),
        ],
      ),
    );
    if (go == true && mounted) await Nav.openReader(context, book);
  }

  Widget _page(String name) {
    if (name == '我的') return const MePage();
    final b = MainTabs.builders[name];
    if (b != null) return Builder(builder: b);
    return Center(child: Text('$name（待移植）'));
  }

  // SF Symbols of the original (book, magnifyingglass.circle, safari, bookmark, person; `.fill` when selected) as Material icons
  static const _defaultIcons = {
    '书架': (Icons.book_outlined, Icons.book),
    '发现': (Icons.saved_search_outlined, Icons.saved_search),
    '探索': (Icons.explore_outlined, Icons.explore),
    '订阅': (Icons.bookmark_border, Icons.bookmark),
    '我的': (Icons.person_outline, Icons.person),
  };

  Widget _icon(ThemeProvider tp, String name, bool selected) {
    final icons = _defaultIcons[name]!;
    final file = tp.tabIcon(ThemeProvider.tabNames.indexOf(name), selected: selected);
    if (file.isNotEmpty) {
      final f = File(file);
      if (f.existsSync()) return Image.file(f, width: 24, height: 24, errorBuilder: (_, _, _) => Icon(icons.$1));
    }
    return Icon(selected ? icons.$2 : icons.$1);
  }

  @override
  Widget build(BuildContext context) {
    final tp = ThemeProvider.instance;
    final index = Common.index.value.clamp(0, _tabs.length - 1);
    _pages.putIfAbsent(_tabs[index], () => _page(_tabs[index])); // tabs are built on first visit and then kept alive
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in _tabs) KeyedSubtree(key: ValueKey('page_$t'), child: _pages[t] ?? const SizedBox.shrink())],
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: MainPage.showBottom,
        builder: (context, show, _) => !show
            ? const SizedBox.shrink()
            : ListenableBuilder(
                listenable: tp,
                builder: (context, _) => NavigationBar(
                  selectedIndex: index,
                  backgroundColor: tp.tabBarColor,
                  indicatorColor: tp.tabBarSelectedColor?.withValues(alpha: 0.18),
                  labelBehavior: tp.showTitleWhenUnselected
                      ? NavigationDestinationLabelBehavior.alwaysShow
                      : (tp.showTitleWhenSelected
                          ? NavigationDestinationLabelBehavior.onlyShowSelected
                          : NavigationDestinationLabelBehavior.alwaysHide),
                  onDestinationSelected: (i) => Common.index.value = i,
                  destinations: [
                    for (final name in _tabs)
                      NavigationDestination(
                        key: Key('tab_$name'),
                        icon: _icon(tp, name, false),
                        selectedIcon: _icon(tp, name, true),
                        label: name,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
