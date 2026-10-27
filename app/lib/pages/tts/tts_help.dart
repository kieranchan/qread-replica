// pages/tts/tts_help.dart — `TTSHelpPage` (3 functions): shows a code block with 复制 (`代码已复制到剪贴板`). Used for the engine
// template help and for exporting engines.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/toast.dart';

class TTSHelpPage extends StatelessWidget {
  final String title;
  final String code;
  const TTSHelpPage({super.key, this.title = '帮助', this.code = template});

  /// A Legado-style HttpTTS definition (what 本地导入 accepts).
  static const String template = '''[
  {
    "name": "示例引擎",
    "url": "https://example.com/tts?text={{java.encodeURI(speakText)}}&rate={{speakSpeed}}",
    "header": "{\\"User-Agent\\":\\"Mozilla/5.0\\"}",
    "contentType": "audio/.*"
  },
  {
    "name": "POST 示例",
    "url": "https://example.com/tts,{\\"method\\":\\"POST\\",\\"body\\":\\"text={{speakText}}&speed={{speakSpeed * 2}}\\"}"
  }
]
// 可用变量：speakText（朗读文本）、speakSpeed（语速，10 为正常）、speakVolume、voice
// 可用函数：java.encodeURI、encodeURIComponent、java.base64Encode、java.md5Encode、Math.round 等''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            Toast.show('代码已复制到剪贴板');
          },
        ),
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      ),
    );
  }
}
