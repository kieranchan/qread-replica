// pages/replace/replace_rule_help.dart — "净化帮助" (original `ReplaceRuleHelp`, build 0x95d97c): title 轻悦时光替换净化规则, two sections
// 替换规则 / 替换内容 with the original texts and the code block a `@js:` replacement runs in.
import 'package:flutter/material.dart';

class ReplaceRuleHelp extends StatelessWidget {
  const ReplaceRuleHelp({super.key});

  static const String ruleText = '目前支持正则替换和简单的字符串替换，如果需要正则替换，请勾选使用正则表达式';
  static const String contentText = '目前支持简单的字符串替换和js替换，如果要使用js替换请在开头添加@js:（只有正则替换才支持js），使用js替换则会执行以下代码：';
  static const String jsCode = 'var result="正则匹配的内容";\n你的js代码';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('轻悦时光替换净化规则'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title('替换规则'),
          const Text(ruleText),
          title('替换内容'),
          const Text(contentText),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.surfaceContainerHighest,
            child: const SelectableText(jsCode, style: TextStyle(fontFamily: 'monospace')),
          ),
        ]),
      ),
    );
  }
}
