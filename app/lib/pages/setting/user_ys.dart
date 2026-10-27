// pages/setting/user_ys.dart — 用户协议 / 免责声明 page (`UserAgreementPage`). The original ships a long agreement; this replica is a
// personal-use rebuild, so the page only states that (the original text is deliberately not copied). Section titles follow the
// original's structure (欢迎使用轻悦时光 / 重要提醒 / 内容责任声明 / 隐私政策 / 其他条款).
import 'package:flutter/material.dart';

class UserAgreementPage extends StatefulWidget {
  final String title;
  const UserAgreementPage({super.key, this.title = '免责声明'});

  @override
  State<UserAgreementPage> createState() => _UserAgreementPageState();
}

class _UserAgreementPageState extends State<UserAgreementPage> {
  static const List<(String, String)> sections = [
    ('重要提醒', '本应用是个人使用的复刻版本，仅供开发者本人学习与使用，与原应用及其开发者、运营方没有任何关联，也不代表其立场。'),
    ('内容责任声明', '应用本身不提供任何书籍、音频或其他内容资源。通过书源、订阅源或网盘获取的内容均来自用户自行配置的第三方，其合法性由内容提供方及使用者自行负责。'),
    ('隐私政策', '应用不包含统计、广告或追踪功能。账号与云端数据仅保存在使用者自己的服务器上；第三方服务（如 AI 接口、朗读引擎、WebDAV）的密钥只保存在本机设置中，并只发送给使用者配置的服务。'),
    ('其他条款', '本应用按现状提供，不作任何担保。使用即表示理解并接受上述说明。'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('欢迎使用轻悦时光', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('个人自用复刻版，与原应用无关', style: TextStyle(color: cs.outline)),
        const SizedBox(height: 20),
        for (final s in sections) ...[
          Text(s.$1, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(s.$2, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 18),
        ],
      ]),
    );
  }
}
