// pages/user/user_edit_page.dart — edit nickname and avatar (`updateNickname`, `updateAvatar?tockenid=`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/userapi.dart';
import '../../data/user.dart';
import '../../qread/http.dart';
import '../../util/toast.dart';

class UserEditPage extends StatefulWidget {
  const UserEditPage({super.key});

  @override
  State<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends State<UserEditPage> {
  late final TextEditingController _nick = TextEditingController(text: UserSession.nickname);

  Future<void> _pickAvatar() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (f == null) return;
    try {
      await UserApi.updateAvatar(await f.readAsBytes(), f.name);
      Toast.show('头像已更新');
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  Future<void> _saveNick() async {
    final n = _nick.text.trim();
    if (n.isEmpty) return Toast.show('请输入昵称');
    try {
      await UserApi.updateNickname(n);
      Toast.show('保存成功');
      Get.back();
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: const Text('个人资料')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 44,
                backgroundImage: UserSession.avatarUrl.isNotEmpty ? NetworkImage(UserSession.avatarUrl) : null,
                child: UserSession.avatarUrl.isEmpty ? const Icon(Icons.add_a_photo_outlined) : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(key: const Key('edit_nick'), controller: _nick, decoration: const InputDecoration(labelText: '昵称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          ListTile(title: const Text('用户名'), trailing: Text(UserSession.username)),
          ListTile(title: const Text('邮箱'), trailing: Text(UserSession.email)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _saveNick, child: const Text('保存')),
        ]),
      ),
    );
  }
}
