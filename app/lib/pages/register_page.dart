// pages/register_page.dart — 邮箱 / 用户名 / 密码 / 验证码. On the owner's server the 6-digit code is an invite code issued by
// the admin (`qread-admin make-codes invite`), not an e-mail code.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api/userapi.dart';
import '../qread/http.dart';
import '../util/toast.dart';
import 'user/account_validators.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _getCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) return Toast.show('请输入您的邮箱');
    try {
      await UserApi.getEmailCode(email);
      Toast.show('请向管理员索取 6 位验证码');
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  Future<void> _register() async {
    // 0x7f3480 / 0x7f3370 / 0x7f300c: the original's field checks
    final err = AccountValidators.username(_user.text) ??
        AccountValidators.email(_email.text) ??
        AccountValidators.password(_pass.text) ??
        AccountValidators.confirm(_pass.text, _pass2.text);
    if (err != null) return Toast.show(err);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text.trim())) return Toast.show('请输入6位数字验证码');
    setState(() => _busy = true);
    try {
      await UserApi.register(username: _user.text.trim(), email: _email.text.trim(), password: _pass.text, code: _code.text.trim());
      Toast.show('注册成功，请登录您的账户');
      if (mounted) Get.back();
    } on ApiException catch (e) {
      Toast.show('注册失败：${e.message}', iserror: true);
    } on QHttpException catch (e) {
      Toast.show('注册失败：${e.message}', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _user, _pass, _pass2, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // 0x7f0d7c: 创建账户 / 请填写以下信息创建您的账户
        const Text('创建账户', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('请填写以下信息创建您的账户', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        TextField(
          key: const Key('reg_email'),
          controller: _email,
          decoration: const InputDecoration(labelText: '邮箱', hintText: '请输入您的邮箱', border: OutlineInputBorder()),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        TextField(key: const Key('reg_user'), controller: _user, decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(key: const Key('reg_pass'), controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: '密码', hintText: '请输入密码', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(key: const Key('reg_pass2'), controller: _pass2, obscureText: true, decoration: const InputDecoration(labelText: '确认密码', hintText: '请再次输入密码', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('reg_code'),
              controller: _code,
              decoration: const InputDecoration(labelText: '验证码', hintText: '请输入6位数字验证码', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: _getCode, child: const Text('获取验证码')),
        ]),
        const SizedBox(height: 20),
        FilledButton(key: const Key('reg_go'), onPressed: _busy ? null : _register, child: Text(_busy ? '注册中…' : '注册')),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('已有账户？'),
          TextButton(onPressed: () => Get.back(), child: const Text('立即登录')),
        ]),
      ]),
    );
  }
}
