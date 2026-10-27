// pages/source/source_help.dart — `SourceHelpPage` (StatelessWidget, size 0x20): help for writing sources. The original's help
// content is not in the snapshot strings (it is loaded from the vendor's site); the replica shows a local summary of the source
// kinds and the Legado rule syntax that the replica's engine implements.
import 'package:flutter/material.dart';

class SourceHelpPage extends StatelessWidget {
  final String title;
  const SourceHelpPage({super.key, this.title = '书源帮助'});

  static const List<(String, String)> sections = [
    (
      '书源类型',
      '轻悦时光书源（时光源）：软件原生的书源，由 html 代码（或网址）实现搜索、发现、详情、目录、正文等函数，运行在网页引擎中。\n'
          '阅读兼容层书源（阅读源）：开源阅读（Legado）格式的书源，由本机的规则引擎直接运行。\n'
          '轻阅读后端书源：存放在您自己部署的轻阅读后端里的书源，由后端运行，需要先在「轻阅读后端绑定」中绑定。'
    ),
    (
      '规则写法',
      'CSS 选择器：`.list li@text`、`a@href`、`img@src`，`@css:` 前缀可显式声明。\n'
          'XPath：以 `//` 或 `@XPath:` 开头。\n'
          'JSONPath：以 `\$.` / `\$[` 或 `@json:` 开头。\n'
          'JavaScript：`<js>…</js>` 或 `@js:…`，`result` 是上一步的结果，`java.*`、`source.*`、`cookie.*` 等对象可用。\n'
          '正则：`##正则##替换` 净化结果，`:正则` 开头为 AllInOne 规则。\n'
          '变量：`@put:{key:rule}` 保存，`@get:{key}` 读取，`{{ }}` 内可写 JS 或规则。'
    ),
    (
      '地址规则',
      '搜索地址：`/search?q={{key}}&page={{page}}`，POST 时写成 `url,{"method":"POST","body":"q={{key}}"}`，'
          '还可以指定 `charset`、`headers`、`webView`。\n'
          '发现地址：每行 `名称::地址`，或 JSON 数组 `[{"title":"…","url":"…"}]`，也可以由 JS 生成。'
    ),
    (
      '调试',
      '在书源编辑页点「调试」：输入关键字调试搜索；输入详情页网址调试详情；`++目录网址` 调试目录；`--正文网址` 调试正文；'
          '`名称::发现网址` 调试发现。调试页可开启在线调试 HTTP 服务（端口 5858），同一局域网的电脑可以调用接口调试和保存书源。'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in sections) ...[
            Text(s.$1, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            SelectableText(s.$2, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
