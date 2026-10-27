// util/webbook/analyze_rule/analyze_by_xpath.dart - `//div[@class='x']/a/@href`, `./td[2]/text()`, `@xpath:` rules. Node results are
// kept as [XNode]s so that list items can be used as the context of the item rules (`./a/@href`).
import 'package:html/dom.dart' as dom;

import '../../html/jsoup.dart';
import '../../html/xpath.dart';
import 'rule_analyzer.dart';

class AnalyzeByXPath {
  final dom.Node _node;

  AnalyzeByXPath(Object doc) : _node = parse(doc);

  /// Wraps the input: XNode/Element -> as is; strings are parsed as HTML (table fragments get a `<table>` wrapper like Legado does).
  static dom.Node parse(Object doc) {
    if (doc is XNode) {
      final n = doc.node;
      if (n != null && (n is dom.Element || n is dom.Document)) return n;
      return parseHtml(doc.asString());
    }
    if (doc is dom.Element || doc is dom.Document) return doc as dom.Node;
    var html = doc.toString();
    if (html.endsWith('</td>')) html = '<tr>$html</tr>';
    if (html.endsWith('</tr>') || html.endsWith('</tbody>')) html = '<table>$html</table>';
    return parseHtml(html);
  }

  List<XNode>? getElements(String xPath) {
    if (xPath.isEmpty) return null;
    final ruleAnalyzes = RuleAnalyzer(xPath);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);
    if (rules.length == 1) {
      return XPath.compile(rules[0]).select(_node);
    }
    final jxNodes = <XNode>[];
    final results = <List<XNode>>[];
    for (final rl in rules) {
      final temp = getElements(rl);
      if (temp != null && temp.isNotEmpty) {
        results.add(temp);
        if (ruleAnalyzes.elementsType == '||') break;
      }
    }
    if (results.isNotEmpty) {
      if (ruleAnalyzes.elementsType == '%%') {
        for (var i = 0; i < results[0].length; i++) {
          for (final t in results) {
            if (i < t.length) jxNodes.add(t[i]);
          }
        }
      } else {
        for (final t in results) {
          jxNodes.addAll(t);
        }
      }
    }
    return jxNodes;
  }

  List<String> getStringList(String xPath) {
    final result = <String>[];
    final ruleAnalyzes = RuleAnalyzer(xPath);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);
    if (rules.length == 1) {
      return XPath.compile(xPath).select(_node).map((n) => n.asString()).toList();
    }
    final results = <List<String>>[];
    for (final rl in rules) {
      final temp = getStringList(rl);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (ruleAnalyzes.elementsType == '||') break;
      }
    }
    if (results.isNotEmpty) {
      if (ruleAnalyzes.elementsType == '%%') {
        for (var i = 0; i < results[0].length; i++) {
          for (final t in results) {
            if (i < t.length) result.add(t[i]);
          }
        }
      } else {
        for (final t in results) {
          result.addAll(t);
        }
      }
    }
    return result;
  }

  String? getString(String rule) {
    final ruleAnalyzes = RuleAnalyzer(rule);
    final rules = ruleAnalyzes.splitRule(['&&', '||']);
    if (rules.length == 1) {
      final nodes = XPath.compile(rule).select(_node);
      if (nodes.isEmpty) return null;
      return nodes.map((n) => n.asString()).join('\n');
    }
    final textList = <String>[];
    for (final rl in rules) {
      final temp = getString(rl);
      if (temp != null && temp.isNotEmpty) {
        textList.add(temp);
        if (ruleAnalyzes.elementsType == '||') break;
      }
    }
    return textList.join('\n');
  }
}
