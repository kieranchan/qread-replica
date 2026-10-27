// pages/self_check_page.dart — 诊断自检: runs util/self_check.dart, shows ✓/✗ per check, and can report the results to the server.
import 'package:flutter/material.dart';

import '../api/userapi.dart';
import '../data/user.dart';
import '../qread/http.dart';
import '../util/self_check.dart';
import '../util/toast.dart';

class SelfCheckPage extends StatefulWidget {
  const SelfCheckPage({super.key});

  @override
  State<SelfCheckPage> createState() => _SelfCheckPageState();
}

class _SelfCheckPageState extends State<SelfCheckPage> {
  List<CheckResult> _results = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final r = await SelfCheck.run();
    if (!mounted) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  Future<void> _report() async {
    if (!UserSession.isLoggedIn) return Toast.show('登录后才能上报');
    try {
      final r = await UserApi.diag(_results);
      Toast.show('已上报：通过 ${r['ok']}，失败 ${r['fail']}');
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _results.where((r) => !r.ok).length;
    return Scaffold(
      appBar: AppBar(title: const Text('诊断自检')),
      body: ListView(children: [
        ListTile(
          key: const Key('self_check_summary'),
          title: Text(_busy ? '检查中…' : (failed == 0 ? '全部通过' : '$failed 项失败')),
          subtitle: Text(SelfCheck.appVersion),
        ),
        for (final r in _results)
          ListTile(
            key: Key('check_${r.name}'),
            leading: Icon(r.ok ? Icons.check_circle : Icons.error, color: r.ok ? Colors.green : Colors.red),
            title: Text(r.name),
            subtitle: Text(r.detail),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: OutlinedButton(key: const Key('self_check_again'), onPressed: _busy ? null : _run, child: const Text('重新检查'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(key: const Key('self_check_report'), onPressed: _busy || _results.isEmpty ? null : _report, child: const Text('上报到服务器'))),
          ]),
        ),
      ]),
    );
  }
}
