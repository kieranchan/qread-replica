// util/webbook/analyze_rule/analyze_by_jsoup.dart - the default ("legacy") rule syntax: `class.x.0@tag.a@href`, `@css:`, `!` exclusion,
// index lists `[0,2:5]`, `&&` `||` `%%`. Vocabulary in the original: class tag id text children textNodes ownText html all script style.
import 'package:html/dom.dart' as dom;

import '../../html/css_select.dart';
import '../../html/jsoup.dart';
import '../../html/xpath.dart';
import 'rule_analyzer.dart';

class AnalyzeByJSoup {
  final dom.Node _element;

  AnalyzeByJSoup(Object doc) : _element = parse(doc);

  /// `doc` may be an Element/Document, an XPath node wrapper (anything with `element`), or a String of HTML.
  static dom.Node parse(Object doc) {
    if (doc is dom.Element || doc is dom.Document) return doc as dom.Node;
    if (doc is XNode) {
      final n = doc.node;
      if (n is dom.Element || n is dom.Document) return n!;
      return parseHtml(doc.asString());
    }
    return parseHtml(doc.toString());
  }

  List<dom.Element> getElements(String rule) => _getElements(_element, rule);

  String? getString(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    final list = getStringList(ruleStr);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    return list.join('\n');
  }

  List<String> getStringList(String ruleStr) {
    final textS = <String>[];
    if (ruleStr.isEmpty) return textS;
    final sourceRule = _SourceRule(ruleStr);
    if (sourceRule.elementsRule.isEmpty) {
      textS.add(jData(_element));
    } else {
      final ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule);
      final ruleStrS = ruleAnalyzes.splitRule(['&&', '||', '%%']);
      final results = <List<String>>[];
      for (final ruleStrX in ruleStrS) {
        List<String>? temp;
        if (sourceRule.isCss) {
          final lastIndex = ruleStrX.lastIndexOf('@');
          if (lastIndex < 0) {
            temp = _getResultLast(CssSelector.parse(ruleStrX).select(_element), 'text');
          } else {
            temp = _getResultLast(CssSelector.parse(ruleStrX.substring(0, lastIndex)).select(_element), ruleStrX.substring(lastIndex + 1));
          }
        } else {
          temp = _getResultList(ruleStrX);
        }
        if (temp != null && temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }
      if (results.isNotEmpty) {
        if (ruleAnalyzes.elementsType == '%%') {
          for (var i = 0; i < results[0].length; i++) {
            for (final t in results) {
              if (i < t.length) textS.add(t[i]);
            }
          }
        } else {
          for (final t in results) {
            textS.addAll(t);
          }
        }
      }
    }
    return textS;
  }

  List<dom.Element> _getElements(dom.Node? temp, String rule) {
    if (temp == null || rule.isEmpty) return [];
    final elements = <dom.Element>[];
    final sourceRule = _SourceRule(rule);
    final ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule);
    final ruleStrS = ruleAnalyzes.splitRule(['&&', '||', '%%']);
    final elementsList = <List<dom.Element>>[];
    if (sourceRule.isCss) {
      for (final ruleStr in ruleStrS) {
        final tempS = CssSelector.parse(ruleStr).select(temp);
        elementsList.add(tempS);
        if (tempS.isNotEmpty && ruleAnalyzes.elementsType == '||') break;
      }
    } else {
      for (final ruleStr in ruleStrS) {
        final rsRule = RuleAnalyzer(ruleStr);
        rsRule.trim();
        final rs = rsRule.splitRule(['@']);
        List<dom.Element> el;
        if (rs.length > 1) {
          var cur = <dom.Node>[temp];
          for (final rl in rs) {
            final es = <dom.Element>[];
            for (final et in cur) {
              es.addAll(_getElements(et, rl));
            }
            cur = es;
          }
          el = cur.cast<dom.Element>();
        } else {
          el = _ElementsSingle().getElementsSingle(temp, ruleStr);
        }
        elementsList.add(el);
        if (el.isNotEmpty && ruleAnalyzes.elementsType == '||') break;
      }
    }
    if (elementsList.isNotEmpty) {
      if (ruleAnalyzes.elementsType == '%%') {
        for (var i = 0; i < elementsList[0].length; i++) {
          for (final es in elementsList) {
            if (i < es.length) elements.add(es[i]);
          }
        }
      } else {
        for (final es in elementsList) {
          elements.addAll(es);
        }
      }
    }
    return elements;
  }

  List<String>? _getResultList(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    var elements = <dom.Node>[_element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);
    final last = rules.length - 1;
    for (var i = 0; i < last; i++) {
      final es = <dom.Element>[];
      for (final elt in elements) {
        es.addAll(_ElementsSingle().getElementsSingle(elt, rules[i]));
      }
      elements = es;
    }
    if (elements.isEmpty) return null;
    return _getResultLast(elements.cast<dom.Element>(), rules[last]);
  }

  List<String> _getResultLast(List<dom.Element> elements, String lastRule) {
    final textS = <String>[];
    switch (lastRule) {
      case 'text':
        for (final e in elements) {
          textS.add(jText(e));
        }
        break;
      case 'textNodes':
        for (final e in elements) {
          final tn = <String>[];
          for (final t in jTextNodes(e)) {
            final text = t.trim();
            if (text.isNotEmpty) tn.add(text);
          }
          if (tn.isNotEmpty) textS.add(tn.join('\n'));
        }
        break;
      case 'ownText':
        for (final e in elements) {
          textS.add(jOwnText(e));
        }
        break;
      case 'html':
        for (final q in const ['script', 'style']) {
          final sel = CssSelector.parse(q);
          for (final e in elements) {
            for (final m in sel.select(e)) {
              m.remove();
            }
          }
        }
        textS.add(elements.map(jOuterHtml).join('\n'));
        break;
      case 'all':
        textS.add(elements.map(jOuterHtml).join('\n'));
        break;
      default:
        for (final e in elements) {
          final url = jAttr(e, lastRule);
          if (url.trim().isEmpty || textS.contains(url)) continue;
          textS.add(url);
        }
    }
    return textS;
  }
}

class _SourceRule {
  bool isCss = false;
  late final String elementsRule;

  _SourceRule(String ruleStr) {
    if (ruleStr.length >= 5 && ruleStr.substring(0, 5).toLowerCase() == '@css:') {
      isCss = true;
      elementsRule = ruleStr.substring(5).trim();
    } else {
      elementsRule = ruleStr;
    }
  }
}

/// One rule step (`class.name.0`, `tag.a!0:2`, `div[1,-1]` ...): selector part plus index set; `!` excludes, `.` selects.
class _ElementsSingle {
  String split = '.';
  String beforeRule = '';
  final List<int> indexDefault = [];
  final List<Object> indexes = []; // int or (int?, int?, int) range

  List<dom.Element> getElementsSingle(dom.Node temp, String rule) {
    _findIndexSet(rule);
    List<dom.Element> elements;
    if (beforeRule.isEmpty) {
      elements = jChildren(temp);
    } else {
      final rules = beforeRule.split('.');
      switch (rules[0]) {
        case 'children':
          elements = jChildren(temp);
          break;
        case 'class':
          elements = getElementsByClass(temp, rules.length > 1 ? rules[1] : '');
          break;
        case 'tag':
          elements = getElementsByTag(temp, rules.length > 1 ? rules[1] : '');
          break;
        case 'id':
          elements = getElementsById(temp, rules.length > 1 ? rules[1] : '');
          break;
        case 'text':
          elements = getElementsContainingOwnText(temp, rules.length > 1 ? rules[1] : '');
          break;
        default:
          elements = CssSelector.parse(beforeRule).select(temp);
      }
    }
    final len = elements.length;
    final lastIndexes = indexDefault.isNotEmpty ? indexDefault.length - 1 : indexes.length - 1;
    final indexSet = <int>{};
    if (indexes.isEmpty) {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final it = indexDefault[ix];
        if (it >= 0 && it < len) {
          indexSet.add(it);
        } else if (it < 0 && len >= -it) {
          indexSet.add(it + len);
        }
      }
    } else {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final item = indexes[ix];
        if (item is (int?, int?, int)) {
          final (startX, endX, stepX) = item;
          int start;
          if (startX == null) {
            start = 0;
          } else if (startX >= 0) {
            start = startX < len ? startX : len - 1;
          } else if (-startX <= len) {
            start = len + startX;
          } else {
            start = 0;
          }
          int end;
          if (endX == null) {
            end = len - 1;
          } else if (endX >= 0) {
            end = endX < len ? endX : len - 1;
          } else if (-endX <= len) {
            end = endX + len;
          } else {
            end = 0;
          }
          if (start == end || stepX >= len) {
            indexSet.add(start);
            continue;
          }
          final stp = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1);
          if (end > start) {
            for (var i = start; i <= end; i += stp) {
              indexSet.add(i);
            }
          } else {
            for (var i = start; i >= end; i -= stp) {
              indexSet.add(i);
            }
          }
        } else {
          final it = item as int;
          if (it >= 0 && it < len) {
            indexSet.add(it);
          } else if (it < 0 && len >= -it) {
            indexSet.add(it + len);
          }
        }
      }
    }
    if (split == '!') {
      final out = <dom.Element>[];
      for (var i = 0; i < len; i++) {
        if (!indexSet.contains(i)) out.add(elements[i]);
      }
      return out;
    } else if (split == '.') {
      final es = <dom.Element>[];
      for (final p in indexSet) {
        if (p >= 0 && p < len) es.add(elements[p]);
      }
      return es;
    }
    return elements;
  }

  void _findIndexSet(String rule) {
    final rus = rule.trim();
    if (rus.isEmpty) {
      split = ' ';
      beforeRule = rus;
      return;
    }
    var len = rus.length;
    int? curInt;
    var curMinus = false;
    final curList = <int?>[];
    var l = '';
    final head = rus[rus.length - 1] == ']';

    int cu(int i) => rus.codeUnitAt(i);

    if (head) {
      len--; // skip the trailing ']'
      while (len-- > 0) {
        var rl = rus[len];
        if (rl == ' ') continue;
        if (cu(len) >= 0x30 && cu(len) <= 0x39) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          curInt = l.isEmpty ? null : (curMinus ? -int.parse(l) : int.parse(l));
          if (rl == ':') {
            curList.add(curInt);
          } else {
            if (curList.isEmpty) {
              if (curInt == null) break;
              indexes.add(curInt);
            } else {
              indexes.add((curInt, curList.last, curList.length == 2 ? curList.first ?? 1 : 1));
              curList.clear();
            }
            if (rl == '!') {
              split = '!';
              do {
                len--;
                if (len < 0) break;
                rl = rus[len];
              } while (len > 0 && rl == ' ');
            }
            if (rl == '[') {
              beforeRule = rus.substring(0, len);
              return;
            }
            if (rl != ',') break;
          }
          l = '';
          curMinus = false;
        }
      }
      // not a valid index structure: treat the whole rule as the selector
      indexes.clear();
      split = ' ';
      beforeRule = rus;
      return;
    }
    while (len-- > 0) {
      final rl = rus[len];
      if (rl == ' ') continue;
      if (cu(len) >= 0x30 && cu(len) <= 0x39) {
        l = rl + l;
      } else if (rl == '-') {
        curMinus = true;
      } else {
        if (rl == '!' || rl == '.' || rl == ':') {
          if (l.isEmpty) {
            // `tag.a.` or `x:` without number: not an index structure
            break;
          }
          indexDefault.add(curMinus ? -int.parse(l) : int.parse(l));
          if (rl != ':') {
            split = rl;
            beforeRule = rus.substring(0, len);
            return;
          }
        } else {
          break;
        }
        l = '';
        curMinus = false;
      }
    }
    indexDefault.clear();
    split = ' ';
    beforeRule = rus;
  }
}
