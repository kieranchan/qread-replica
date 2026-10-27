// pages/theme/theme_plaza_page.dart — 主题广场 (`ThemePlazaPage`, state 0x81be9c): category chips (全部 + `public/categories`), a mode
// filter (全部 / 白天 / 夜间, `theme_mode`), a paged grid of `public/themes` (20 per page, next page when the end is reached) with the
// preview image, name and author (`匿名` when empty). Tapping opens the detail page.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme_api.dart';
import 'theme_detail_page.dart';

class ThemePlazaPage extends StatefulWidget {
  const ThemePlazaPage({super.key});

  /// Factory of the client (tests point it at a local server).
  static ThemePlazaApi Function() api = () => ThemePlazaApi();

  @override
  State<ThemePlazaPage> createState() => _ThemePlazaPageState();
}

class _ThemePlazaPageState extends State<ThemePlazaPage> {
  final ThemePlazaApi _api = ThemePlazaPage.api();
  final ScrollController _scroll = ScrollController();
  List<ThemeCategory> _categories = [];
  int _category = 0;

  /// 0 = 全部, 1 = 白天, 2 = 夜间.
  int _mode = 0;
  final List<PlazaTheme> _items = [];
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _load();
    });
    _api.categories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _more = true;
      _error = '';
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    try {
      final r = await _api.themes(page: _page + 1, limit: 20, categoryId: _category);
      if (!mounted) return;
      setState(() {
        _page = r.page;
        _more = r.hasMore && r.items.isNotEmpty;
        _items.addAll(r.items);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PlazaTheme> get _visible => switch (_mode) {
        1 => _items.where((t) => !t.isNight).toList(),
        2 => _items.where((t) => t.isNight).toList(),
        _ => _items,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('主题广场'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _mode,
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _mode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('全部')),
              PopupMenuItem(value: 1, child: Text('白天')),
              PopupMenuItem(value: 2, child: Text('夜间')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final c in [const ThemeCategory(0, '全部'), ..._categories])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: _category == c.id,
                  onSelected: (_) {
                    _category = c.id;
                    _reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: items.isEmpty && !_loading
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error.isNotEmpty ? _error : '暂无主题', style: TextStyle(color: cs.outline))),
                  ])
                : GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200, childAspectRatio: 0.62, mainAxisSpacing: 10, crossAxisSpacing: 10),
                    itemCount: items.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= items.length) return const Center(child: CircularProgressIndicator());
                      final t = items[i];
                      return Card(
                        key: Key('plaza_${t.id}'),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Get.to(() => ThemeDetailPage(theme: t, api: _api)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(
                              child: t.imagePath.isEmpty
                                  ? Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.palette_outlined, size: 40))
                                  : Image.network(_api.fileUrl(t.imagePath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined))),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                              child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Row(children: [
                                Expanded(
                                  child: Text(t.author.isEmpty ? '匿名' : t.author,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.outline)),
                                ),
                                Text(t.isNight ? '夜间' : '白天', style: TextStyle(fontSize: 11, color: cs.primary)),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
