// pages/user/cloud_setting_page.dart — cloud switches. Every switch is member-only: `if (!isvip) toast("此功能为会员功能")`;
// turning one on also asks the server (`canOpenCloud`), which is the real permission check on the owner's server.
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../data/user.dart';
import '../../qread/http.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';

class CloudSettingPage extends StatelessWidget {
  const CloudSettingPage({super.key});

  Future<void> _toggle(String key, bool value) async {
    if (value && !Vip.require()) return;
    if (value) {
      try {
        if (!await UserApi.canOpenCloud()) return Toast.show('云端功能需要会员权限', iserror: true);
      } on QHttpException catch (e) {
        return Toast.show(e.message, iserror: true);
      }
    }
    await UserSession.setSwitch(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) {
        Widget sw(String title, String key, bool v) =>
            SwitchListTile(key: Key('sw_$key'), title: Text(title), value: v, onChanged: (x) => _toggle(key, x));
        return Scaffold(
          appBar: AppBar(title: const Text('云端设置')),
          body: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('云端功能需要会员权限，开启后将自动同步数据到云端，确保多设备数据一致', style: TextStyle(color: Colors.grey)),
            ),
            sw('云端书架', PrefKeys.cloudbookself, UserSession.cloudbookself),
            sw('云端书源', PrefKeys.cloudsource, UserSession.cloudsource),
            sw('云端书签', PrefKeys.cloudmark, UserSession.cloudmark),
            sw('云端排版', PrefKeys.cloudtheme, UserSession.cloudtheme),
            sw('云端朗读引擎', PrefKeys.cloudtts, UserSession.cloudtts),
            sw('进度同步', PrefKeys.autoSyncProgressEnabled, UserSession.autoSyncProgressEnabled),
          ]),
        );
      },
    );
  }
}
