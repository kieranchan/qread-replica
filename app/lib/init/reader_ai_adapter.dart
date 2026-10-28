// init/reader_ai_adapter.dart — backs the reader's AI chat (`ReaderAi`) with the AI module: the user's own OpenAI-compatible model
// configs (`Setting.getAiModels`, the 模型管理 page) and `OpenAiClient` streaming. Lead-owned glue (see wiring.dart).
import '../ai/chat/chat_agent.dart';
import '../ai/openai_client.dart';
import '../models/ai_model_config.dart';
import '../pages/read/reader_ai.dart';
import '../storage/setting.dart';

class ReaderAiAdapter implements ReaderAi, ReaderAiTools {
  List<AiModelConfig> get _configs => [for (final m in Setting.getAiModels()) if (OpenAiClient(m).configured) m];

  @override
  List<ReaderAiModel> get models => [for (final m in _configs) ReaderAiModel(m.id, m.name.isEmpty ? m.model : m.name)];

  AiModelConfig _pick(String? modelId) {
    final configs = _configs;
    if (configs.isEmpty) throw const AiException('请先在模型管理中添加模型');
    return configs.firstWhere((m) => m.id == modelId, orElse: () => configs.first);
  }

  /// The chat sheet's tools (reading-settings changes, read_setting_tools.dart) through the AI module's tool loop.
  @override
  Stream<String> chatWithTools(List<Map<String, String>> messages, List<ChatTool> tools, {String? modelId, bool deep = false}) =>
      ChatAgent.chatWithTools(_pick(modelId), messages, tools, deep: deep);

  @override
  Stream<String> chat(List<Map<String, String>> messages, {String? modelId, bool deep = false}) async* {
    final configs = _configs;
    if (configs.isEmpty) throw const AiException('请先在模型管理中添加模型');
    final config = configs.firstWhere((m) => m.id == modelId, orElse: () => configs.first);
    final client = OpenAiClient(config);
    final msgs = [for (final m in messages) AiMessage(m['role'] ?? 'user', m['content'] ?? '')];
    await for (final d in client.chatStream(msgs, thinking: deep)) {
      if (d.text.isNotEmpty) yield d.text;
    }
  }
}
