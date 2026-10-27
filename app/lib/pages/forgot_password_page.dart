// pages/forgot_password_page.dart — 忘记密码: the owner's server has no mail sender, so it answers "请联系管理员重置密码".
import 'package:flutter/material.dart';

import '../api/userapi.dart';
import '../qread/http.dart';
import '../util/toast.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) return Toast.show('请输入您的邮箱');
    try {
      await UserApi.forgetPassword(email);
      Toast.show('已发送，请查收邮件');
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: _email, decoration: const InputDecoration(labelText: '邮箱', hintText: '请输入您的邮箱', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        FilledButton(onPressed: _submit, child: const Text('提交')),
      ]),
    );
  }
}
