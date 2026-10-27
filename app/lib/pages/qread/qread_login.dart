// pages/qread/qread_login.dart — 轻阅读后端绑定: binds the app to the user's own 轻阅读 backend (base url, username, password).
// Original `_QReadLoginPageState` (build 0x658fb4, validators 0x65dc34/0x65dc0c/0x65dbe4, submit 0x100d894, prefill 0x10ce1b4 reads
// `Qreadurl`/`Qreadusername`/`Qreadpassword`). The help button of the original opens the vendor's documentation page; the replica
// shows the same information locally instead (no vendor service is contacted).
import 'package:flutter/material.dart';

import '../../qread/qread.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';

class QReadLoginPage extends StatefulWidget {
  const QReadLoginPage({super.key});

  @override
  State<QReadLoginPage> createState() => _QReadLoginPageState();
}

class _QReadLoginPageState extends State<QReadLoginPage> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// 0x10ce1b4: the last bound values.
  Future<void> _prefill() async {
    if (!Storage.ready) return;
    await Qread.load();
    final pass = await Qread.savedPassword();
    if (!mounted) return;
    setState(() {
      _url.text = Qread.url;
      _user.text = Qread.username;
      _pass.text = pass;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    debugPrint('后端地址: ${_url.text}');
    debugPrint('用户名: ${_user.text}');
    setState(() => _busy = true);
    try {
      await Qread.bind(_url.text, _user.text.trim(), _pass.text);
      if (!mounted) return;
      Toast.show('绑定成功');
      Navigator.of(context).pop(true);
    } on QreadException catch (e) {
      Toast.show(e.message, iserror: true);
    } catch (e) {
      Toast.show('绑定失败:$e', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // TODO(asm 0x100d7b4): the original launches the vendor documentation page here.
  Future<void> _launchHelpUrl() => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('查看帮助文档'),
          content: const SingleChildScrollView(
            child: Text('轻阅读后端是把开源阅读的书源引擎做成服务端的程序，需要您自己部署。\n\n'
                '后端地址：部署后的访问地址，例如 http://192.168.1.2:8080，可以填写多个（用逗号分隔），绑定时依次尝试。\n'
                '用户名 / 密码：后端里创建的账户。\n\n'
                '绑定后，书源管理和订阅中会出现后端的书源（标记 📶），编辑后端书源需要后台给当前用户授权。'),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
        ),
      );

  Future<void> _unbind() async {
    await Qread.unbind();
    if (mounted) setState(() {});
    Toast.show('已解除绑定');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), backgroundColor: Colors.transparent, elevation: 0),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cs.primaryContainer, cs.surface])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('轻阅读后端绑定', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text('连接到您的轻阅读服务器', textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const Key('qread_url'),
                          controller: _url,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: '后端地址', hintText: 'http://example.com:8080', border: OutlineInputBorder(), prefixIcon: Icon(Icons.dns_outlined)),
                          validator: (v) => (v ?? '').trim().isEmpty ? '请输入后端地址' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('qread_user'),
                          controller: _user,
                          decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                          validator: (v) => (v ?? '').trim().isEmpty ? '请输入用户名' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('qread_pass'),
                          controller: _pass,
                          obscureText: _hide,
                          decoration: InputDecoration(
                            labelText: '密码',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _hide = !_hide)),
                          ),
                          validator: (v) => (v ?? '').isEmpty ? '请输入密码' : null,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          key: const Key('qread_bind'),
                          onPressed: _busy ? null : _submitForm,
                          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('绑定'),
                        ),
                        if (Qread.isbind) TextButton(onPressed: _unbind, child: Text('解除绑定（当前：${Qread.username}）')),
                        TextButton(onPressed: _launchHelpUrl, child: const Text('查看帮助文档')),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
