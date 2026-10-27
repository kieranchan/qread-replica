// models/txt_toc_rule.dart — a TXT chapter-title rule. Fields and JSON keys from the original (docs/MODELS.md);
// `detxtTocRules` is the static default list of the original (initializer sub_61f71c, pool pp+0x32b28..0x32bb8):
// 10 rules, the first one (`目录(去空白,内置禁止修改)`) cannot be deleted, all are enabled.
import '_json.dart';

class TxtTocRule {
  String name;
  String rule;
  bool candel;
  bool isEnabled;

  TxtTocRule({
    this.name = '',
    this.rule = '',
    this.candel = false,
    this.isEnabled = false,
  });

  factory TxtTocRule.fromJson(Map<String, dynamic> json) => TxtTocRule(
        name: jStr(json['name']),
        rule: jStr(json['rule']),
        candel: jBool(json['candel']),
        isEnabled: jBool(json['isEnabled']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'rule': rule,
        'candel': candel,
        'isEnabled': isEnabled,
      };

  TxtTocRule copy() => TxtTocRule(name: name, rule: rule, candel: candel, isEnabled: isEnabled);

  /// A fresh copy of the built-in rule list (callers mutate rules, so every call builds new objects).
  static List<TxtTocRule> defaults() => [
    TxtTocRule(name: '目录(去空白,内置禁止修改)', rule: r'(?<=[\u3000\s])(?:序章|序言|卷首语|扉页|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$', candel: false, isEnabled: true),
    TxtTocRule(name: '目录', rule: r'^[ \u3000\t]{0,4}(?:序章|序言|卷首语|扉页|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$', candel: true, isEnabled: true),
    TxtTocRule(name: '数字 分隔符 标题名称', rule: r'^[ \u3000\t]{0,4}\d{1,5}[：:,.， 、_—\\-].{1,30}$', candel: true, isEnabled: true),
    TxtTocRule(name: '大写数字 分隔符 标题名称', rule: r'^[ \u3000\t]{0,4}(?:序章|序言|卷首语|扉页|楔子|正文(?!完|结)|终章|后记|尾声|番外|[〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 、_—\\-].{1,30}$', candel: true, isEnabled: true),
    TxtTocRule(name: '正文 标题/序号', rule: r'^[ \u3000\t]{0,4}正文[ \u3000]{1,4}.{0,20}$', candel: true, isEnabled: true),
    TxtTocRule(name: 'Chapter/Section/Part/Episode 序号 标题', rule: r'^[ \u3000\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO]\.|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$', candel: true, isEnabled: true),
    TxtTocRule(name: '特殊符号 序号 标题', rule: r'(?<=[\s\u3000])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$', candel: true, isEnabled: true),
    TxtTocRule(name: '特殊符号 标题(单个)', rule: r'(?<=[\s\u3000]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ \u3000]{0,4}$', candel: true, isEnabled: true),
    TxtTocRule(name: '章/卷 序号 标题', rule: r'^[ \t\u3000]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|序言|卷首语|扉页|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ \u3000]{0,4}.{0,30}$', candel: true, isEnabled: true),
    TxtTocRule(name: '标题 特殊符号 序号', rule: r'^.{1,20}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ \u3000\t]{0,4}$', candel: true, isEnabled: true),
      ];

  /// `TxtTocRule.detxtTocRules` (static 0x4af0): the built-in list, shared and never modified in place.
  static final List<TxtTocRule> detxtTocRules = defaults();
}
