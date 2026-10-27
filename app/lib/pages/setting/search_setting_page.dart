// pages/setting/search_setting_page.dart — 书源设置 (`SeachSettingPage`, 85 functions). Prefs written by the setters 0x1028d98 …
// 0x102a9ec (all text values):
//   预缓存 / 缓存章数 `cachebook` (default 5, `阅读时预先缓存的数量，如果书源不允许下载请设置为0。`)
//   自动更新 `autoupdate` + 更新间隔 `autoupdateInterval` (hours, `请输入不小于1的数字`)
//   段评气泡 → choose_svg.dart (`svg` = chosen bubble id, 0x102a218)
//   后端绑定 (已绑定 / 未绑定, `允许绑定轻阅读后端来解析开源阅读书源`) → `Nav.openNamed('qread_login')`
//   本地兼容层（实验性） `needben`; 新增书源 `addSourcePosition` (插入最前 / 插入最后)
//   搜索线程 `searchpppl` (6), 更新线程 `updateThread`, 缓存线程 `cacheThread` (2), 换源线程 `changeSourceThread` (4) — `请输入 1 ~ 16 之间的整数`
//   名称覆盖 `nameOverride`, 分组覆盖 `groupOverride`, 发现样式 `discoveryStyle`, `webviewDelayOpen`.
// A failed load shows `加载设置失败: …`.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/common.dart';
import '../../common/nav.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import 'choose_svg.dart';

class SeachSettingPage extends StatefulWidget {
  const SeachSettingPage({super.key});

  static const List<(String, String, String, int)> threads = [
    ('searchpppl', '搜索线程', '搜索时多少个书源同时搜索，请不要调太大以免发热软件崩溃', 6),
    ('updateThread', '更新线程', '更新书籍时同时更新的书源数量，请不要调太大以免发热软件崩溃', 1),
    ('cacheThread', '缓存线程', '缓存章节时同时缓存的线程数量，请不要调太大以免发热软件崩溃', 2),
    ('changeSourceThread', '换源线程', '换源时同时尝试的书源数量，请不要调太大以免发热软件崩溃', 4),
  ];

  @override
  State<SeachSettingPage> createState() => _SeachSettingPageState();
}

class _SeachSettingPageState extends State<SeachSettingPage> {
  bool _bound = false;

  @override
  void initState() {
    super.initState();
    _loadBind();
  }

  Future<void> _loadBind() async {
    try {
      final v = await Storage.read('Qreadisbind${Common.appid}');
      if (mounted) setState(() => _bound = v.trim() == 'true');
    } catch (e) {
      Toast.show('加载设置失败: $e', iserror: true);
    }
  }

  Future<void> _int(String key, String title, int def, {int min = 0, int? max, String? error}) async {
    final v = await Dialogs.input(context, title, initial: '${Storage.getInt(key, def)}', keyboardType: TextInputType.number);
    if (v == null) return;
    final n = int.tryParse(v.trim());
    if (n == null || n < min || (max != null && n > max)) {
      Toast.show(error ?? (max == null ? '请输入不小于$min的数字' : '请输入 $min ~ $max 之间的整数'), iserror: true);
      return;
    }
    await Storage.setInt(key, n);
    if (mounted) setState(() {});
  }

  Widget _switch(String key, String title, String sub, {bool def = false}) => SwitchListTile(
        title: Text(title),
        subtitle: Text(sub),
        value: Storage.getBool(key, def),
        onChanged: (v) async {
          await Storage.setBool(key, v);
          setState(() {});
        },
      );

  @override
  Widget build(BuildContext context) {
    final pos = Storage.getInt('addSourcePosition', 0);
    return Scaffold(
      appBar: AppBar(title: const Text('书源设置')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SectionCard(title: '预缓存', children: [
          ListTile(
            key: const Key('ss_cachebook'),
            title: const Text('缓存章数'),
            subtitle: const Text('阅读时预先缓存的数量，如果书源不允许下载请设置为0。'),
            trailing: Text('${Storage.getInt('cachebook', 5)} 章'),
            onTap: () => _int('cachebook', '预缓存章数', 5, min: 0),
          ),
        ]),
        SectionCard(title: '自动更新', children: [
          _switch('autoupdate', '自动更新', '是否自动刷新书架书本的目录，可设置更新时间。'),
          ListTile(
            title: const Text('更新间隔'),
            subtitle: const Text('自动更新的时间间隔，单位：小时，最小1小时。'),
            trailing: Text('${Storage.getInt('autoupdateInterval', 1)} 小时'),
            onTap: () => _int('autoupdateInterval', '更新间隔（小时）', 1, min: 1, error: '请输入不小于1的数字'),
          ),
        ]),
        SectionCard(title: '书源', children: [
          ListTile(
            title: const Text('段评气泡'),
            subtitle: const Text('书源显示的段评气泡'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Get.to(() => const ChooseSvgPage()),
          ),
          ListTile(
            title: const Text('后端绑定'),
            subtitle: const Text('允许绑定轻阅读后端来解析开源阅读书源'),
            trailing: Text(_bound ? '已绑定' : '未绑定'),
            onTap: () async {
              await Nav.openNamed(context, 'qread_login');
              _loadBind();
            },
          ),
          _switch('needben', '本地兼容层（实验性）', '阅读兼容层目前为测试功能，可能会在后续版本归于仅会员使用'),
          ListTile(
            title: const Text('新增书源'),
            subtitle: const Text('添加新的书源到列表'),
            trailing: Text(pos == 0 ? '插入最前' : '插入最后'),
            onTap: () async {
              final i = await Dialogs.choose(context, '新增书源位置', ['插入最前', '插入最后'], selected: pos);
              if (i == null) return;
              await Storage.setInt('addSourcePosition', i);
              Toast.show('新增书源位置已设置为${i == 0 ? '插入最前' : '插入最后'}');
              setState(() {});
            },
          ),
          _switch('nameOverride', '名称覆盖', '导入书源时是否使用新书源名称'),
          _switch('groupOverride', '分组覆盖', '导入书源时是否使用新书源分组'),
        ]),
        SectionCard(title: '搜索设置', children: [
          for (final t in SeachSettingPage.threads)
            ListTile(
              key: Key('ss_${t.$1}'),
              title: Text(t.$2),
              subtitle: Text(t.$3),
              trailing: Text('${Storage.getInt(t.$1, t.$4)}'),
              onTap: () => _int(t.$1, t.$2, t.$4, min: 1, max: 16),
            ),
        ]),
      ]),
    );
  }
}
