// pages/replace/replace_rule_help.dart — "净化帮助" (original `replace_rule_help.dart`). TODO(asm replace_rule_help): the original help text
// is a long pool string that was not extracted; this page summarises the rule semantics implemented by `ReplaceRuleEngine`.
import 'package:flutter/material.dart';

class ReplaceRuleHelp extends StatelessWidget {
  const ReplaceRuleHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('净化帮助')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          '替换规则：匹配的文字会被替换为“替换为”中的内容，“替换为”留空即删除。\n\n'
          '使用正则表达式：开启后按正则匹配，替换内容可用 \$1、\$2 引用分组。\n\n'
          '作用于：选择规则作用于标题和/或正文。\n\n'
          '替换范围：填写书名或书源 URL，多个用逗号分隔，留空表示全部书籍。\n\n'
          '排除范围：填写的书名或书源 URL 不使用此规则。\n\n'
          '超时毫秒数：单条规则执行超过该时间会被停用，防止复杂正则卡住阅读。',
        ),
      ),
    );
  }
}
