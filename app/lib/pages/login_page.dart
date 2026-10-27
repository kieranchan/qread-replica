// pages/login_page.dart — 用户名/邮箱 + 密码 (original strings), links to register / forgot password.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api/userapi.dart';
import '../data/user.dart';
import '../qread/http.dart';
import '../util/toast.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty) return Toast.show('请输入用户名或邮箱');
    if (p.isEmpty) return Toast.show('请输入密码');
    setState(() => _busy = true);
    try {
      final info = await UserApi.login(u, p);
      await UserSession.apply(info);
      Toast.show('登录成功');
      if (mounted) Get.back(result: true);
    } on ApiException catch (e) {
      Toast.show('登录失败: ${e.message}', iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 24),
        TextField(
          key: const Key('login_user'),
          controller: _user,
          decoration: const InputDecoration(labelText: '用户名/邮箱', hintText: '请输入用户名或邮箱', border: OutlineInputBorder()),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('login_pass'),
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 20),
        FilledButton(key: const Key('login_go'), onPressed: _busy ? null : _login, child: Text(_busy ? '登录中…' : '登录')),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: () => Get.to(() => const ForgotPasswordPage()), child: const Text('忘记密码？')),
          TextButton(onPressed: () => Get.to(() => const RegisterPage()), child: const Text('立即注册')),
        ]),
      ]),
    );
  }
}
