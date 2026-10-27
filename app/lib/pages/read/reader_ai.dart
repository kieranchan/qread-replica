// pages/read/reader_ai.dart — the language model as the reader's AI chat sees it.
//
// The original's chat sheet calls the AI module (`lib/ai/`, owned by another area) with the user's own OpenAI-compatible model configs
// (`aiModelList`). The reader only needs "send these messages, stream the answer", so it talks to [ReaderAi]. [ReaderAi.instance] is
// null until the app wires the AI module; the sheet then shows the original's "未配置模型" / "请先在模型管理中添加模型".
class ReaderAiModel {
  final String id;
  final String name;
  const ReaderAiModel(this.id, this.name);
}

abstract class ReaderAi {
  /// Set by the app (null = not configured).
  static ReaderAi? instance;

  /// The models the user configured (the chat's model picker; the first is "默认").
  List<ReaderAiModel> get models;

  /// Streams the answer to [messages] (`{"role": "system"|"user"|"assistant", "content": ...}`). [deep] = "深度" (thinking) mode.
  Stream<String> chat(List<Map<String, String>> messages, {String? modelId, bool deep = false});
}
