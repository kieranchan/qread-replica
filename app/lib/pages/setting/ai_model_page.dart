// pages/setting/ai_model_page.dart — AI模型配置 (`AiModelPage`, 47 functions): the OpenAI-compatible models of `Setting.getAiModels()`.
// Each card shows 模型 n / name, badges 多角色 / 净化, 接口地址 / 密钥 (masked) / 模型 or `尚未填写配置`, and the actions 编辑 / 删除
// (`确定要删除 "x" 吗？`) / 检验 (0x109208c: `正在检验模型...` → `检验成功，模型配置正常` / `检验失败: …` / `检验超时，请检查网络或重试`;
// incomplete: `请先填写完整的接口地址、密钥和模型`) / 设为默认多角色分析模型 / 设为默认正文净化模型. The editor (添加模型 / 编辑模型):
// 名称（可选） `如 OpenAI、Claude`, 接口地址 (`接口地址必须以 completions 结尾`, 0x1091d3c), 密钥 `输入密钥`, 模型
// `如 gpt-3.5-turbo、gpt-4、GLM-4-Flash`, 并发. 云端备份: 上传备份 / 下载恢复 of the item `ai_model_settings_v2`
// (`备份将保存当前AI模型配置到云端，方便在其他设备上恢复使用`; member-gated like every cloud item).
import 'package:flutter/material.dart';

import '../../ai/openai_client.dart';
import '../../api/userapi.dart';
import '../../data/list_store.dart';
import '../../data/user.dart';
import '../../models/ai_model_config.dart';
import '../../qread/http.dart';
import '../../storage/setting.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';

class AiModelPage extends StatefulWidget {
  const AiModelPage({super.key});

  /// Hook for the check (tests replace it).
  static Future<String?> Function(AiModelConfig) test = OpenAiClient.testModel;

  @override
  State<AiModelPage> createState() => _AiModelPageState();
}

class _AiModelPageState extends State<AiModelPage> {
  List<AiModelConfig> _models = Setting.getAiModels();
  final Set<String> _checking = {};

  Future<void> _save() async {
    await Setting.saveAiModels(_models);
    setState(() => _models = Setting.getAiModels());
  }

  Future<void> _edit([AiModelConfig? old]) async {
    final name = TextEditingController(text: old?.name ?? '');
    final url = TextEditingController(text: old?.url ?? '');
    final key = TextEditingController(text: old?.key ?? '');
    final model = TextEditingController(text: old?.model ?? '');
    final conc = TextEditingController(text: '${(old?.concurrent ?? 0) <= 0 ? 1 : old!.concurrent}');
    var obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(old == null ? '添加模型' : '编辑模型'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(key: const Key('ai_name'), controller: name, decoration: const InputDecoration(labelText: '名称（可选）', hintText: '如 OpenAI、Claude')),
                TextField(
                    key: const Key('ai_url'),
                    controller: url,
                    decoration: const InputDecoration(labelText: '接口地址', hintText: '如 https://api.openai.com/v1/chat/completions')),
                TextField(
                  key: const Key('ai_key'),
                  controller: key,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '密钥',
                    hintText: '输入密钥',
                    suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setS(() => obscure = !obscure)),
                  ),
                ),
                TextField(key: const Key('ai_model'), controller: model, decoration: const InputDecoration(labelText: '模型', hintText: '如 gpt-3.5-turbo、gpt-4、GLM-4-Flash')),
                TextField(controller: conc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '并发')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            TextButton(key: const Key('ai_ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final u = url.text.trim();
    if (u.isNotEmpty && !OpenAiClient.validUrl(u)) return Toast.show('接口地址必须以 completions 结尾', iserror: true);
    final c = AiModelConfig(
      id: old?.id ?? newId(),
      name: name.text.trim(),
      url: u,
      key: key.text.trim(),
      model: model.text.trim(),
      isRoleAnalysis: old?.isRoleAnalysis ?? _models.isEmpty,
      isPurify: old?.isPurify ?? _models.isEmpty,
      concurrent: int.tryParse(conc.text.trim()) ?? 1,
    );
    final i = _models.indexWhere((m) => m.id == c.id);
    if (i < 0) {
      _models.add(c);
    } else {
      _models[i] = c;
    }
    await _save();
  }

  Future<void> _delete(AiModelConfig m) async {
    final title = m.name.isEmpty ? '未命名模型' : m.name;
    if (!await Dialogs.confirm(context, '删除模型', '确定要删除 "$title" 吗？', danger: true)) return;
    _models.removeWhere((e) => e.id == m.id);
    await _save();
  }

  Future<void> _check(AiModelConfig m) async {
    if (m.url.isEmpty || m.key.isEmpty || m.model.isEmpty) return Toast.show('请先填写完整的接口地址、密钥和模型', iserror: true);
    setState(() => _checking.add(m.id));
    Toast.show('正在检验模型...');
    final err = await AiModelPage.test(m);
    if (mounted) setState(() => _checking.remove(m.id));
    Toast.show(err ?? '检验成功，模型配置正常', iserror: err != null);
  }

  Future<void> _setDefault(AiModelConfig m, {required bool role}) async {
    for (final e in _models) {
      if (role) {
        e.isRoleAnalysis = e.id == m.id;
      } else {
        e.isPurify = e.id == m.id;
      }
    }
    await _save();
  }

  Future<void> _upload() async {
    if (!UserSession.isLoggedIn) return Toast.show('请先登录', iserror: true);
    if (!Vip.require()) return;
    try {
      await UserApi.setItemJsonFile(Setting.aiBackupItem, Setting.buildAiBackup());
      Toast.show('备份成功');
    } on ApiException catch (e) {
      Toast.show('备份失败: ${e.message}', iserror: true);
    } on QHttpException catch (e) {
      Toast.show('备份失败: ${e.message}', iserror: true);
    }
  }

  Future<void> _download() async {
    if (!UserSession.isLoggedIn) return Toast.show('请先登录', iserror: true);
    if (!Vip.require()) return;
    try {
      final n = await Setting.restoreAiBackup(await UserApi.getItemJson(Setting.aiBackupItem));
      setState(() => _models = Setting.getAiModels());
      Toast.show('已恢复 $n 个模型');
    } on FormatException catch (e) {
      Toast.show(e.message, iserror: true);
    } on ApiException catch (e) {
      Toast.show(e.message, iserror: true);
    } on QHttpException catch (e) {
      Toast.show(e.message, iserror: true);
    }
  }

  static String _mask(String key) => key.length <= 8 ? '••••' : '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';

  Widget _card(int i, AiModelConfig m) {
    final cs = Theme.of(context).colorScheme;
    final empty = m.url.isEmpty && m.key.isEmpty && m.model.isEmpty;
    Widget badge(String t) => Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
        );
    return Card(
      key: Key('ai_card_${m.id}'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(child: Text(m.name.isEmpty ? '模型 ${i + 1}' : m.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (m.isRoleAnalysis) badge('多角色'),
                if (m.isPurify) badge('净化'),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(m);
                  case 'delete':
                    _delete(m);
                  case 'role':
                    _setDefault(m, role: true);
                  case 'purify':
                    _setDefault(m, role: false);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'role', child: Text('设为默认多角色分析模型')),
                PopupMenuItem(value: 'purify', child: Text('设为默认正文净化模型')),
                PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
              ],
            ),
          ]),
          if (empty)
            Text('尚未填写配置', style: TextStyle(color: cs.outline))
          else ...[
            Text('接口地址：${m.url}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('密钥：${m.key.isEmpty ? '-' : _mask(m.key)}', style: const TextStyle(fontSize: 12)),
            Text('模型：${m.model}', style: const TextStyle(fontSize: 12)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('ai_check_${m.id}'),
              onPressed: _checking.contains(m.id) ? null : () => _check(m),
              icon: _checking.contains(m.id)
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.verified_outlined, size: 18),
              label: const Text('检验'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI模型配置'), actions: [
        IconButton(key: const Key('ai_add'), tooltip: '添加模型', icon: const Icon(Icons.add), onPressed: () => _edit()),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text('AI 能力由您配置的第三方模型提供，本应用不提供合成生成服务', style: TextStyle(fontSize: 12, color: cs.outline)),
        ),
        for (var i = 0; i < _models.length; i++) _card(i, _models[i]),
        if (_models.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('请先在模型管理中添加模型', style: TextStyle(color: cs.outline)))),
        SectionCard(title: '云端备份', children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('备份将保存当前AI模型配置到云端，方便在其他设备上恢复使用', style: TextStyle(fontSize: 12, color: cs.outline)),
          ),
          Row(children: [
            Expanded(child: TextButton.icon(onPressed: _upload, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('上传备份'))),
            Expanded(child: TextButton.icon(onPressed: _download, icon: const Icon(Icons.cloud_download_outlined), label: const Text('下载恢复'))),
          ]),
        ]),
      ]),
    );
  }
}
