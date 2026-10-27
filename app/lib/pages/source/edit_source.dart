// pages/source/edit_source.dart — `EditSource`: picks the editor for a source (`late Widget w`, state size 0x50), the source kinds,
// and the `请选择书源类型` dialog of the manager (0x54d324).
//
// Kinds of the original (names from the page-id table 0x6bdc40):
//   时光源 `editsgsource` 时光编辑书源 — native source, an html engine page (`html` field)          -> edit_sgsource.dart
//   阅读源 `editbqsource` 兼容层编辑书源 — 开源阅读 (Legado) JSON; the original marks it `@yuedu`      -> edit_bqsource.dart
//   后端源 `editqsource`  后端编辑书源   — stored on the bound 轻阅读 backend (`isqread`)          -> edit_qsource.dart
// The replica stores Legado JSON as is, so a source is a 时光源 when it has an `html` engine (not `@yuedu…`) and no Legado rules.
import 'package:flutter/material.dart';

import '../../data/qsource.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../qread/qread.dart';
import '../../util/toast.dart';
import 'edit_bqsource.dart';
import 'edit_qsource.dart';
import 'edit_sgsource.dart';

enum SourceKind { sg, bq, q }

const Set<String> _legadoKeys = {'searchUrl', 'exploreUrl', 'ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent', 'bookSourceType'};

/// The kind of a stored source map.
SourceKind sourceKindOf(Map<String, dynamic> raw) {
  if (raw['isqread'] == true || '${raw['isqread']}' == 'true') return SourceKind.q;
  final html = '${raw['html'] ?? ''}'.trim();
  if (html.isNotEmpty && !html.startsWith('@yuedu') && !raw.keys.any(_legadoKeys.contains)) return SourceKind.sg;
  return SourceKind.bq;
}

/// The `📶` / `📒` marks of the lists (0x54839c): backend sources and 阅读源; 时光源 have none.
String sourceMark(SourceKind k) => switch (k) {
      SourceKind.q => '📶',
      SourceKind.bq => '📒',
      SourceKind.sg => '',
    };

class EditSource extends StatefulWidget {
  /// Raw JSON of the source (null = new; then [kind] chooses the editor).
  final Map<String, dynamic>? source;
  final SourceKind? kind;
  const EditSource({super.key, this.source, this.kind});

  @override
  State<EditSource> createState() => _EditSourceState();
}

class _EditSourceState extends State<EditSource> {
  late Widget w;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    final kind = widget.kind ?? (s == null ? SourceKind.bq : sourceKindOf(s));
    w = switch (kind) {
      SourceKind.sg => EditSgSourcePage(source: s),
      SourceKind.q => EditQSourcePage(url: '${s?['bookSourceUrl'] ?? ''}'),
      SourceKind.bq => EditBqSourcePage(source: s),
    };
  }

  @override
  Widget build(BuildContext context) => w;
}

/// 0x54d324 `请选择书源类型`: the kinds the user may create (the backend one only when bound).
Future<SourceKind?> chooseSourceKind(BuildContext context) {
  final bound = Qread.isbind;
  return showDialog<SourceKind>(
    context: context,
    builder: (c) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('请选择书源类型', textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 16),
          ElevatedButton(key: const Key('kind_sg'), onPressed: () => Navigator.of(c).pop(SourceKind.sg), child: const Text('轻悦时光书源')),
          const SizedBox(height: 8),
          ElevatedButton(key: const Key('kind_bq'), onPressed: () => Navigator.of(c).pop(SourceKind.bq), child: const Text('阅读兼容层书源')),
          if (bound) ...[
            const SizedBox(height: 8),
            ElevatedButton(key: const Key('kind_q'), onPressed: () => Navigator.of(c).pop(SourceKind.q), child: const Text('轻阅读后端书源')),
          ],
          const SizedBox(height: 12),
          Text(
            bound
                ? '注：轻阅读后端是将开源阅读代码转成服务端web，兼容率较高。\n时光兼容层是基于时光书源函数进行兼容阅读书源，兼容率没有后端高，运行速度较慢。\n轻悦时光书源为软件原生书源兼容最好，建议支持使用轻悦时光书源。'
                : '注：时光兼容层是基于时光书源函数进行兼容阅读书源，运行速度较慢。\n轻悦时光书源为软件原生书源兼容最好，建议支持使用轻悦时光书源。',
            style: TextStyle(fontSize: 12, height: 1.5, color: Theme.of(c).colorScheme.outline),
          ),
        ]),
      ),
    ),
  );
}

/// Target of `Nav.openSourceEdit`: the editor of [source] (null = new source, after the kind dialog). Backend sources need the
/// edit permission (`当前用户无法编辑轻阅读书源…`, 0xf8dee4).
Future<void> openSourceEdit(BuildContext context, Source? source) async {
  Map<String, dynamic>? raw;
  SourceKind? kind;
  if (source == null) {
    kind = await chooseSourceKind(context);
    if (kind == null) return;
  } else {
    await Sourcedata.load();
    raw = Sourcedata.byUrl(source.bookSourceUrl);
    if (raw == null && (source.isqread || QSources.byUrl(source.bookSourceUrl) != null)) {
      raw = {...source.toJson(), 'isqread': true};
    }
    if (raw == null) {
      Toast.show('未找到书源');
      return;
    }
  }
  if ((kind ?? sourceKindOf(raw!)) == SourceKind.q && !Qread.requireEdit()) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (c) => EditSource(source: raw, kind: kind)));
}
