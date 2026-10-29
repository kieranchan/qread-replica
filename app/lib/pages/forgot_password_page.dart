// pages/forgot_password_page.dart — 忘记密码 (original 0x7b4294 + checks 0x7b58cc): the e-mail form (`重置密码`, `请输入您的邮箱地址，
// 我们将发送密码重置链接到您的邮箱。`), the `邮件已发送` card afterwards (`我们已向 x 发送了密码重置链接。` + the spam-folder hint) and
// `记起密码了？ 返回登录`. The owner's server answers the request itself (docs/API.md `forgetPassword`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api/userapi.dart';
import '../qread/http.dart';
import '../util/toast.dart';
import 'user/account_validators.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _sentTo;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final err = AccountValidators.email(email);
    if (err != null) return Toast.show(err);
    setState(() => _busy = true);
    try {
      await UserApi.forgetPassword(email);
      if (mounted) setState(() => _sentTo = email);
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sent = _sentTo;
    return Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (sent == null) ...[
          const Text('重置密码', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('请输入您的邮箱地址，我们将发送密码重置链接到您的邮箱。', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 20),
          TextField(
            key: const Key('forgot_email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱', hintText: '请输入您的邮箱', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          FilledButton(key: const Key('forgot_go'), onPressed: _busy ? null : _submit, child: Text(_busy ? '发送中…' : '发送重置链接')),
        ] else ...[
          Icon(Icons.mark_email_read_outlined, size: 56, color: cs.primary),
          const SizedBox(height: 12),
          const Text('邮件已发送', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('我们已向 $sent 发送了密码重置链接。', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('请检查您的邮箱并按照邮件中的指示重置密码。如果找不到邮件，请检查垃圾邮件文件夹。', textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Get.back(), child: const Text('返回登录')),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('记起密码了？'),
          TextButton(onPressed: () => Get.back(), child: const Text('返回登录')),
        ]),
      ]),
    );
  }
}
