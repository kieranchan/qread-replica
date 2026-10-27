// pages/setting/listem_setting_page.dart — 听书设置 (`ListenSettingPage`, 11 functions): two switches stored as prefs text
// `"true"`/`"false"`: 后台播放 `允许返回后继续播放音频` (`allplay`, 0x1094b7c) and 同时播放 `允许与其他应用同时播放` (`canreadplay`,
// 0x1094c90, default on). A failed load shows `加载设置失败: …` (0x10e0620).
import 'package:flutter/material.dart';

import '../../storage/storage.dart';
import '../../util/toast.dart';

class ListenSettingPage extends StatefulWidget {
  const ListenSettingPage({super.key});

  static const String allplayKey = 'allplay';
  static const String canreadplayKey = 'canreadplay';

  static bool get allplay => Storage.getBool(allplayKey, false);
  static bool get canreadplay => Storage.getBool(canreadplayKey, true);

  @override
  State<ListenSettingPage> createState() => _ListenSettingPageState();
}

class _ListenSettingPageState extends State<ListenSettingPage> {
  bool _allplay = false;
  bool _canreadplay = true;

  @override
  void initState() {
    super.initState();
    try {
      _allplay = ListenSettingPage.allplay;
      _canreadplay = ListenSettingPage.canreadplay;
    } catch (e) {
      Toast.show('加载设置失败: $e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('听书设置')),
      body: ListView(children: [
        SwitchListTile(
          key: const Key('listen_allplay'),
          title: const Text('后台播放'),
          subtitle: const Text('允许返回后继续播放音频'),
          value: _allplay,
          onChanged: (v) async {
            setState(() => _allplay = v);
            await Storage.setBool(ListenSettingPage.allplayKey, v);
          },
        ),
        SwitchListTile(
          key: const Key('listen_canreadplay'),
          title: const Text('同时播放'),
          subtitle: const Text('允许与其他应用同时播放'),
          value: _canreadplay,
          onChanged: (v) async {
            setState(() => _canreadplay = v);
            await Storage.setBool(ListenSettingPage.canreadplayKey, v);
          },
        ),
      ]),
    );
  }
}
