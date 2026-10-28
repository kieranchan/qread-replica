// pages/read/pages/novel/views/read_setting_tools.dart — the reading-settings tools of 时光 AI 助手 (original `ai/chat/setting_meta.dart`,
// `setting_tools.dart` (`updateTool` 0x7e28f4, `propertySchema` 0x7e2d80, list 0x7e207c) and `read_setting_applier.dart` (0xf9f1c0, called
// by the reader's closure 0x57606c)). The 33 parameters with label, type, range, options and whether they need a new layout are the
// const `ReadingParamMeta`s of the original; the four tools are get_reading_settings, update_typography, update_spacing and
// update_display with the original descriptions and key lists. Results are JSON text for the model.
import 'dart:convert';
import 'dart:io' show Platform;

import '../../../../../ai/chat/chat_agent.dart';
import '../../../../../ai/openai_client.dart';
import '../../../../../read/setting/read_setting.dart';
import '../../../../../storage/storage.dart';

class ReadingParamMeta {
  final String key;
  final String label;

  /// int · double · bool · enum · font · turn
  final String type;
  final num? min;
  final num? max;
  final Map<int, String>? options;

  /// Changing it needs a new pagination.
  final bool relayout;

  const ReadingParamMeta(this.key, this.label, this.type, {this.min, this.max, this.options, this.relayout = false});
}

/// The original's metas (objs `ReadingParamMeta`), in the order of the tool lists.
const List<ReadingParamMeta> readingParams = [
  ReadingParamMeta('fontSize', '字号', 'double', min: 10, max: 55, relayout: true),
  ReadingParamMeta('fontFamily', '字体', 'font', relayout: true),
  ReadingParamMeta('fontWeight', '字重', 'int', min: 100, max: 900, relayout: true),
  ReadingParamMeta('lineHeight', '行高', 'double', min: 1, max: 4, relayout: true),
  ReadingParamMeta('letterSpacing', '字间距', 'double', min: -20, max: 50, relayout: true),
  ReadingParamMeta('paragraphSpacing', '段间距', 'double', max: 100, relayout: true),
  ReadingParamMeta('twoColumns', '双列显示', 'bool', relayout: true),
  ReadingParamMeta('topMargin', '正文上边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('bottomMargin', '正文下边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('leftMargin', '正文左边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('rightMargin', '正文右边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('titleTopMargin', '标题上边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('titleBottomMargin', '标题下边距', 'int', max: 200, relayout: true),
  ReadingParamMeta('titleFontSize', '标题字号增量', 'int', max: 100, relayout: true),
  ReadingParamMeta('titleAlign', '标题对齐', 'enum', options: {0: '左对齐', 1: '居中', 2: '右对齐'}, relayout: true),
  ReadingParamMeta('topSafeDistance', '顶部安全距离', 'int', min: -1, max: 200, relayout: true),
  ReadingParamMeta('bottomSafeDistance', '底部安全距离', 'int', min: -1, max: 200, relayout: true),
  ReadingParamMeta('headerLeftMargin', '页眉左边距', 'int', max: 200),
  ReadingParamMeta('headerRightMargin', '页眉右边距', 'int', max: 200),
  ReadingParamMeta('footerLeftMargin', '页脚左边距', 'int', max: 200),
  ReadingParamMeta('footerRightMargin', '页脚右边距', 'int', max: 200),
  ReadingParamMeta('headerFooterFontSize', '页眉页脚字号', 'int', min: 8, max: 25),
  ReadingParamMeta('showHeader', '显示页眉', 'bool'),
  ReadingParamMeta('showFooter', '显示页脚', 'bool'),
  ReadingParamMeta('hideTitle', '隐藏章节标题', 'bool', relayout: true),
  ReadingParamMeta('eyeCare', '护眼模式', 'bool'),
  ReadingParamMeta('showProgress', '进度显示', 'enum', options: {0: '不显示', 1: '章节进度', 2: '全书进度', 3: '章节和全书进度'}),
  ReadingParamMeta('simplified', '简繁转换', 'enum', options: {0: '原文', 1: '简体', 2: '繁体'}, relayout: true),
  ReadingParamMeta('pageTurnAnimation', '翻页方式', 'turn', relayout: true),
  ReadingParamMeta('pageTurnSpeed', '翻页速度(毫秒)', 'int', max: 1000),
  ReadingParamMeta('underline', '全文划线', 'bool'),
  ReadingParamMeta('underlineStyle', '划线样式', 'enum', options: {0: '无', 1: '实线', 2: '点线', 3: '虚线', 4: '波浪线'}),
  ReadingParamMeta('underlineFullWidth', '划线全宽', 'bool'),
];

final Map<String, ReadingParamMeta> readingParamsByKey = {for (final m in readingParams) m.key: m};

/// The page-turn modes the AI may choose (the bottom menu's list).
Map<int, String> get turnOptions => TurnMode.labels(ios: _isIOS);
bool get _isIOS {
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}

class ApplyResult {
  /// key -> {before, after}
  final Map<String, Map<String, dynamic>> changed;
  final List<String> unknown;
  final bool needRelayout;
  const ApplyResult(this.changed, this.unknown, this.needRelayout);
}

/// Reads and writes the parameters on a live [ReadSetting] (its listeners re-layout the reader).
class ReadSettingApplier {
  final ReadSetting s;

  /// Font families offered to the model (`default` = 系统默认).
  final List<String> fonts;
  const ReadSettingApplier(this.s, {this.fonts = const []});

  Object value(String key) => switch (key) {
        'fontSize' => s.fontSize.toDouble(),
        'fontFamily' => s.fontFamily.isEmpty ? 'default' : s.fontFamily,
        'fontWeight' => s.fontWeight,
        'lineHeight' => s.lineHeight,
        'letterSpacing' => s.letterSpacing,
        'paragraphSpacing' => s.paragraphSpacing,
        'twoColumns' => s.ispad,
        'topMargin' => s.topMargin,
        'bottomMargin' => s.bottomMargin,
        'leftMargin' => s.leftMargin,
        'rightMargin' => s.rightMargin,
        'titleTopMargin' => s.titleTopMargin,
        'titleBottomMargin' => s.titleBottomMargin,
        'titleFontSize' => s.titlefontSize,
        'titleAlign' => s.titleAlign,
        'topSafeDistance' => s.safeTop,
        'bottomSafeDistance' => s.safeBottom,
        'headerLeftMargin' => s.headerLeftMargin,
        'headerRightMargin' => s.headerRightMargin,
        'footerLeftMargin' => s.footerLeftMargin,
        'footerRightMargin' => s.footerRightMargin,
        'headerFooterFontSize' => s.headerFooterFontSize,
        'showHeader' => s.showTop,
        'showFooter' => s.showBottom,
        'hideTitle' => s.hidetitle,
        'eyeCare' => Storage.getBool('eyeCare'),
        'showProgress' => s.showProgress,
        'simplified' => s.simplified,
        'pageTurnAnimation' => s.turn,
        'pageTurnSpeed' => s.pageTurnSpeed,
        'underline' => s.underline,
        'underlineStyle' => s.underlineStyle,
        'underlineFullWidth' => s.underlineFullWidth,
        _ => '',
      };

  /// The value of [raw] for [m], or null when it does not fit.
  Object? _coerce(ReadingParamMeta m, Object? raw) {
    switch (m.type) {
      case 'bool':
        if (raw is bool) return raw;
        if ('$raw' == 'true' || '$raw' == '1') return true;
        if ('$raw' == 'false' || '$raw' == '0') return false;
        return null;
      case 'font':
        final f = '$raw'.trim();
        if (f.isEmpty || f == 'default' || f == '系统默认') return '';
        return fonts.isEmpty || fonts.contains(f) ? f : null;
      case 'enum':
      case 'turn':
        final v = raw is num ? raw.toInt() : int.tryParse('$raw');
        final opts = m.type == 'turn' ? turnOptions : m.options!;
        return v != null && opts.containsKey(v) ? v : null;
      default:
        final n = raw is num ? raw : num.tryParse('$raw');
        if (n == null) return null;
        var c = n.clamp(m.min ?? 0, m.max ?? double.infinity);
        return m.type == 'int' ? c.round() : c.toDouble();
    }
  }

  Future<void> _write(String key, Object v) async {
    switch (key) {
      case 'fontSize':
        await s.setFontSize((v as double).round());
      case 'fontFamily':
        await s.setFontFamily(v as String);
      case 'fontWeight':
        await s.setFontWeight(v as int);
      case 'lineHeight':
        await s.setLineHeight(v as double);
      case 'letterSpacing':
        await s.setLetterSpacing(v as double);
      case 'paragraphSpacing':
        await s.setParagraphSpacing(v as double);
      case 'twoColumns':
        await s.setBool('ispad', v as bool);
      case 'topMargin':
        await s.setMargins(top: v as int);
      case 'bottomMargin':
        await s.setMargins(bottom: v as int);
      case 'leftMargin':
        await s.setMargins(left: v as int);
      case 'rightMargin':
        await s.setMargins(right: v as int);
      case 'titleTopMargin':
        await s.setTitle(top: v as int);
      case 'titleBottomMargin':
        await s.setTitle(bottom: v as int);
      case 'titleFontSize':
        await s.setTitle(size: v as int);
      case 'titleAlign':
        await s.setTitle(align: v as int);
      case 'topSafeDistance':
        await s.setSafeDistance(top: v as int);
      case 'bottomSafeDistance':
        await s.setSafeDistance(bottom: v as int);
      case 'headerLeftMargin':
      case 'headerRightMargin':
      case 'footerLeftMargin':
      case 'footerRightMargin':
      case 'headerFooterFontSize':
        await s.setInt(key, v as int);
      case 'showHeader':
        await s.setHeaderFooter(top: v as bool);
      case 'showFooter':
        await s.setHeaderFooter(bottom: v as bool);
      case 'hideTitle':
        await s.setHidetitle(v as bool);
      case 'eyeCare':
        await Storage.setBool('eyeCare', v as bool);
      case 'showProgress':
        await s.setShowProgress(v as int);
      case 'simplified':
        await s.setSimplified(v as int);
      case 'pageTurnAnimation':
        await s.setTurn(v as int);
      case 'pageTurnSpeed':
        await s.setPageTurnSpeed(v as int);
      case 'underline':
        await s.setBool('underline', v as bool);
      case 'underlineStyle':
        await s.setInt('underlineStyle', v as int);
      case 'underlineFullWidth':
        await s.setBool('underlineFullWidth', v as bool);
    }
  }

  /// Applies the parameters of [args] (0xf9f1c0): unknown keys are reported ("未知参数："), values clamped to the range.
  Future<ApplyResult> apply(Map<String, dynamic> args) async {
    final changed = <String, Map<String, dynamic>>{};
    final unknown = <String>[];
    var relayout = false;
    for (final e in args.entries) {
      final m = readingParamsByKey[e.key];
      if (m == null) {
        unknown.add(e.key);
        continue;
      }
      final v = _coerce(m, e.value);
      if (v == null) {
        unknown.add(e.key);
        continue;
      }
      final before = value(e.key);
      await _write(e.key, v);
      changed[e.key] = {'before': before, 'after': value(e.key)};
      if (m.relayout) relayout = true;
    }
    return ApplyResult(changed, unknown, relayout);
  }

  /// get_reading_settings: value, type, range and options of the asked (or all) parameters.
  Map<String, dynamic> describe([List<String>? keys]) {
    final list = keys == null || keys.isEmpty ? readingParams : [for (final k in keys) ?readingParamsByKey[k]];
    return {
      'settings': {
        for (final m in list)
          m.key: {
            'label': m.label,
            'value': value(m.key),
            'type': m.type,
            'min': ?m.min,
            'max': ?m.max,
            if (m.type == 'turn') 'options': {for (final o in turnOptions.entries) '${o.key}': o.value},
            if (m.options != null) 'options': {for (final o in m.options!.entries) '${o.key}': o.value},
            if (m.type == 'font') 'options': ['default', ...fonts],
            'relayout': m.relayout,
          },
      },
    };
  }

  /// JSON schema of one parameter (0x7e2d80).
  Map<String, dynamic> propertySchema(ReadingParamMeta m) {
    switch (m.type) {
      case 'bool':
        return {'type': 'boolean', 'description': m.label};
      case 'font':
        return {'type': 'string', 'description': '${m.label}，可选字体：default=系统默认, ${fonts.join(', ')}'};
      case 'enum':
      case 'turn':
        final opts = m.type == 'turn' ? turnOptions : m.options!;
        return {'type': 'integer', 'description': '${m.label}：${[for (final o in opts.entries) '${o.key}=${o.value}'].join(', ')}'};
      default:
        return {
          'type': m.type == 'int' ? 'integer' : 'number',
          'description': m.label,
          'minimum': ?m.min,
          'maximum': ?m.max,
        };
    }
  }

  ChatTool _updateTool(String name, String description, List<String> keys, void Function(ApplyResult r)? onApplied) => ChatTool(
        AiTool(name, description, {
          'type': 'object',
          'properties': {for (final k in keys) k: propertySchema(readingParamsByKey[k]!)},
        }),
        (args) async {
          if (args.isEmpty) return jsonEncode({'error': '没有提供任何要修改的参数'});
          try {
            final r = await apply(args);
            onApplied?.call(r);
            return jsonEncode({
              'changed': [for (final c in r.changed.entries) '${readingParamsByKey[c.key]!.label} ${c.value['before']}→${c.value['after']}'],
              'needRelayout': r.needRelayout,
              if (r.unknown.isNotEmpty) 'warning': '未知参数：${r.unknown.join('；')}',
            });
          } catch (e) {
            return jsonEncode({'error': '应用失败，$e'});
          }
        },
      );

  /// The four tools of the original list (0x7e207c).
  List<ChatTool> tools({void Function(ApplyResult r)? onApplied}) => [
        ChatTool(
          const AiTool('get_reading_settings', '获取当前阅读参数值及其合法范围（字号、行高、边距、字体清单、翻页方式等）。修改参数前应先调用确认范围。', {
            'type': 'object',
            'properties': {
              'keys': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': '只查指定参数，缺省返回全部',
              },
            },
          }),
          (args) async {
            final keys = args['keys'] is List ? [for (final k in args['keys'] as List) '$k'] : null;
            return jsonEncode(describe(keys));
          },
        ),
        _updateTool(
          'update_typography',
          '修改排版：字号(fontSize 10-55)、字体(fontFamily)、字重(fontWeight 100-900)、行高(lineHeight 1-4)、字间距(letterSpacing)、段间距(paragraphSpacing)、双列(twoColumns)。只传要改的参数。',
          const ['fontSize', 'fontFamily', 'fontWeight', 'lineHeight', 'letterSpacing', 'paragraphSpacing', 'twoColumns'],
          onApplied,
        ),
        _updateTool(
          'update_spacing',
          '修改间距：正文上下左右边距、标题上下间距/字号增量/对齐、顶部底部安全距离(-1=跟随系统)、页眉页脚左右边距与字号。只传要改的参数。',
          const [
            'topMargin', 'bottomMargin', 'leftMargin', 'rightMargin', 'titleTopMargin', 'titleBottomMargin', 'titleFontSize', 'titleAlign', //
            'topSafeDistance', 'bottomSafeDistance', 'headerLeftMargin', 'headerRightMargin', 'footerLeftMargin', 'footerRightMargin',
            'headerFooterFontSize',
          ],
          onApplied,
        ),
        _updateTool(
          'update_display',
          '修改显示：页眉页脚开关、隐藏标题、护眼模式、进度显示方式、简繁转换、翻页方式与速度、全文划线开关/样式/全宽。只传要改的参数。',
          const [
            'showHeader', 'showFooter', 'hideTitle', 'eyeCare', 'showProgress', 'simplified', 'pageTurnAnimation', 'pageTurnSpeed', //
            'underline', 'underlineStyle', 'underlineFullWidth',
          ],
          onApplied,
        ),
      ];
}
