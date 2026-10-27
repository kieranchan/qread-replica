import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/html/css_select.dart';
import 'package:newread/util/html/jsoup.dart';
import 'package:newread/util/html/xpath.dart';
import 'package:newread/util/legado/java_regex.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/legado/json_path.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_by_jsoup.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_by_json_path.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_by_xpath.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_rule.dart';
import 'package:newread/util/webbook/analyze_rule/rule_analyzer.dart';
import 'package:newread/util/webbook/analyze_rule/rule_data.dart';
import 'package:newread/util/webbook/model/book.dart';
import 'package:newread/util/webbook/model/book_chapter.dart';
import 'package:newread/util/webbook/util/network_utils.dart';

const String page = '''
<html><head><title>T</title></head><body>
<div id="main" class="box wide">
  <h1 class="title">Book <b>One</b></h1>
  <ul class="list">
    <li class="item first"><a href="/b/1" title="t1">First</a><span class="tag">a</span></li>
    <li class="item"><a href="/b/2">Second</a><span class="tag">b</span></li>
    <li class="item last"><a href="http://other.example/b/3">Third</a><span class="tag">c</span></li>
  </ul>
  <p class="intro">Line one<br>Line two<!-- c --> tail</p>
  <img src="/c.jpg" alt="cover">
  <div class="empty"></div>
</div></body></html>
''';

void main() {
  setUpAll(() => JsEngines.useDart());

  group('JavaRegex', () {
    test('inline flags, quoting, possessive, posix classes', () {
      expect(JavaRegex.compile('(?i)abc').hasMatch('xABCx'), isTrue);
      expect(JavaRegex.compile(r'\Qa.b\E').hasMatch('a.b'), isTrue);
      expect(JavaRegex.compile(r'\Qa.b\E').hasMatch('axb'), isFalse);
      expect(JavaRegex.compile(r'a++b').hasMatch('aaab'), isTrue);
      expect(JavaRegex.compile(r'\p{Alpha}+').firstMatch('12abc34')!.group(0), 'abc');
      expect(JavaRegex.compile(r'\p{IsHan}+').firstMatch('ab你好cd')!.group(0), '你好');
      expect(JavaRegex.compile(r'(?s)a.b').hasMatch('a\nb'), isTrue);
      expect(JavaRegex.compile(r'\h+').hasMatch(' \t'), isTrue);
    });

    test('replacement strings follow Java', () {
      final re = JavaRegex.compile(r'(\d+)-(\d+)');
      expect(JavaRegex.replaceAll('10-20 30-40', re, r'$2/$1'), '20/10 40/30');
      expect(JavaRegex.replaceAll('a', JavaRegex.compile('a'), r'\$'), r'$');
      expect(() => JavaRegex.replaceAll('a', JavaRegex.compile('a'), r'$1'), throwsFormatException);
      expect(JavaRegex.replaceAll('a-b', JavaRegex.compile(r'(?<x>a)'), r'${x}!'), 'a!-b');
    });
  });

  group('CSS selectors (jsoup flavour)', () {
    final doc = parseHtml(page);
    List<String> texts(String q) => CssSelector.query(q, doc).map(jText).toList();

    test('basic selectors and combinators', () {
      expect(texts('li.item a'), ['First', 'Second', 'Third']);
      expect(texts('ul > li.first > a'), ['First']);
      expect(texts('#main h1'), ['Book One']);
      expect(texts('li.first + li a'), ['Second']);
      expect(texts('li.first ~ li a'), ['Second', 'Third']);
      expect(texts('a[href^=http]'), ['Third']);
      expect(texts('a[href\$="/2"]'), ['Second']);
      expect(texts('a[title]'), ['First']);
      expect(texts('a[href*=b/]').length, 3);
      expect(texts('span.tag, h1'), ['Book One', 'a', 'b', 'c']);
    });

    test('jsoup pseudo selectors', () {
      expect(texts('li:eq(1) a'), ['Second']);
      expect(texts('li:lt(1) a'), ['First']);
      expect(texts('li:gt(1) a'), ['Third']);
      expect(texts('a:contains(Sec)'), ['Second']);
      expect(texts('a:matches(^T)'), ['Third']);
      expect(texts('li:has(a[title])'), ['Firsta']);
      expect(texts('li:not(.first) a'), ['Second', 'Third']);
      expect(texts('li:first-child a'), ['First']);
      expect(texts('li:last-child a'), ['Third']);
      expect(texts('li:nth-child(2) a'), ['Second']);
      expect(texts('li:nth-child(odd) a'), ['First', 'Third']);
      expect(texts('div.empty:empty').length, 1);
    });

    test('malformed selectors throw', () {
      expect(() => CssSelector.parse('li[href'), throwsA(isA<CssSelectException>()));
      expect(() => CssSelector.parse('a:nope'), throwsA(isA<CssSelectException>()));
    });
  });

  group('jsoup text semantics', () {
    final doc = parseHtml(page);
    test('text, ownText, textNodes', () {
      final p = CssSelector.query('p.intro', doc).first;
      expect(jText(p), 'Line one Line two tail');
      expect(jOwnText(p), 'Line one Line two tail');
      expect(jTextNodes(p), ['Line one', 'Line two', ' tail']);
      expect(jText(CssSelector.query('h1', doc).first), 'Book One');
    });
  });

  group('default rule syntax (AnalyzeByJSoup)', () {
    AnalyzeByJSoup a() => AnalyzeByJSoup(page);

    test('class/tag/id with text and attributes', () {
      expect(a().getString('id.main@tag.h1@text'), 'Book One');
      expect(a().getString('class.title@text'), 'Book One');
      expect(a().getString('tag.img@src'), '/c.jpg');
      expect(a().getStringList('class.item@tag.a@text'), ['First', 'Second', 'Third']);
      expect(a().getStringList('class.item@tag.a@href'), ['/b/1', '/b/2', 'http://other.example/b/3']);
    });

    test('index lists and exclusions', () {
      expect(a().getString('class.item.0@tag.a@text'), 'First');
      expect(a().getString('class.item.-1@tag.a@text'), 'Third');
      expect(a().getStringList('class.item!0@tag.a@text'), ['Second', 'Third']);
      expect(a().getStringList('class.item[0,2]@tag.a@text'), ['First', 'Third']);
      expect(a().getStringList('class.item[1:2]@tag.a@text'), ['Second', 'Third']);
      expect(a().getStringList('class.item[-1:0]@tag.a@text'), ['Third', 'Second', 'First']);
      expect(a().getStringList('class.item[!0,1]@tag.a@text'), ['Third']);
      expect(a().getStringList('tag.li.0:1@tag.a@text'), ['First', 'Second']);
    });

    test('text variants', () {
      expect(a().getString('class.intro@ownText'), 'Line one Line two tail');
      expect(a().getString('class.intro@textNodes'), 'Line one\nLine two\ntail');
      final html = a().getString('class.list@html')!;
      expect(html, contains('<li class="item first">'));
      expect(AnalyzeByJSoup(page).getString('class.intro@html'), contains('<br>'));
    });

    test('combinators && || %% and @css', () {
      expect(a().getStringList('class.tag.0@text&&class.title@text'), ['a', 'Book One']);
      expect(a().getString('class.nothing@text||class.title@text'), 'Book One');
      expect(a().getStringList('class.item.0@tag.a@text%%class.item@tag.span@text'), ['First', 'a']);
      expect(a().getStringList('@css:li.item a@text'), ['First', 'Second', 'Third']);
      expect(a().getString('@css:#main > h1@text'), 'Book One');
      expect(a().getStringList('@css:li.item a@href').length, 3);
    });

    test('getElements chains', () {
      expect(a().getElements('class.item').length, 3);
      expect(a().getElements('class.list@tag.li').length, 3);
      expect(a().getElements('tag.li.0:1').length, 2);
      expect(a().getElements('@css:li.item:eq(2)').length, 1);
    });
  });

  group('RuleAnalyzer', () {
    test('splits on separators outside brackets', () {
      final r = RuleAnalyzer('a&&b&&c').splitRule(['&&', '||']);
      expect(r, ['a', 'b', 'c']);
      // only the first separator found counts (Legado behaviour): the rest stays inside the last part
      expect(RuleAnalyzer('a&&b||c').splitRule(['&&', '||']), ['a', 'b||c']);
      final r2 = RuleAnalyzer('class.x[0,1]&&tag.a[?(@.x==1&&@.y)]').splitRule(['&&']);
      expect(r2.length, 2);
      expect(r2[1], 'tag.a[?(@.x==1&&@.y)]');
      expect(RuleAnalyzer('tag.a@href@text').splitRule(['@']), ['tag.a', 'href', 'text']);
    });

    test('inline rules', () {
      final a = RuleAnalyzer(r'x{$.a}y{$.b}z', true);
      final out = a.innerRule(r'{$.', (s) => s == r'$.a' ? 'A' : 'B');
      expect(out, 'xAyBz');
    });
  });

  group('XPath', () {
    final doc = parseHtml(page);
    List<String> sel(String x) => XPath.compile(x).select(doc).map((n) => n.asString()).toList();

    test('paths and attributes', () {
      expect(sel('//li/a/@href'), ['/b/1', '/b/2', 'http://other.example/b/3']);
      expect(sel("//div[@id='main']/h1/text()"), ['Book ']);
      expect(sel('//li[2]/a/text()'), ['Second']);
      expect(sel('//li[last()]/a/text()'), ['Third']);
      expect(sel("//a[contains(@href,'other')]/text()"), ['Third']);
      expect(sel("//li[@class='item first']/a/@title"), ['t1']);
      expect(sel('//li[position()<3]/a/text()'), ['First', 'Second']);
      expect(sel('//a[@title]/text()'), ['First']);
      expect(sel("//span[@class='tag'][.='b']/text()"), ['b']);
    });

    test('axes, unions, functions', () {
      expect(sel("//li[a='Second']/following-sibling::li/a/text()"), ['Third']);
      expect(sel('//li[1]/self::li/@class'), ['item first']);
      expect(sel('//img/parent::div/@id'), ['main']);
      expect(sel('//h1/text() | //img/@alt'), ['Book ', 'cover']);
      expect(sel('count(//li)'), ['3']);
      expect(sel('//li[starts-with(@class,"item")]/a/text()').length, 3);
      expect(sel('normalize-space(//h1)'), ['Book One']);
      expect(sel('//h1/allText()'), ['Book One']);
    });

    test('AnalyzeByXPath getString/getStringList/getElements', () {
      final x = AnalyzeByXPath(page);
      expect(x.getString("//div[@id='main']/h1/b/text()"), 'One');
      expect(x.getStringList('//li/a/text()'), ['First', 'Second', 'Third']);
      final els = x.getElements('//li')!;
      expect(els.length, 3);
      // item-relative rules
      final item = AnalyzeByXPath(els[1]);
      expect(item.getString('./a/text()'), 'Second');
      expect(item.getString('a/@href'), '/b/2');
      expect(item.getString('//span/text()'), 'b');
      expect(x.getStringList('//li/a/text()&&//h1/b/text()'), ['First', 'Second', 'Third', 'One']);
    });
  });

  group('JSONPath', () {
    const json = '''
    {"store":{"book":[
      {"category":"ref","author":"Nigel","title":"Sayings","price":8.95},
      {"category":"fic","author":"Evelyn","title":"Sword","price":12.99,"isbn":"0-553"},
      {"category":"fic","author":"Herman","title":"Moby","price":8.99}],
      "bicycle":{"color":"red","price":19.95}},"expensive":10,"name":"shop"}''';

    test('property, index, wildcard, slice, deep scan', () {
      expect(JsonPath.readFrom(json, r'$.store.bicycle.color'), 'red');
      expect(JsonPath.readFrom(json, r'$.store.book[0].author'), 'Nigel');
      expect(JsonPath.readFrom(json, r'$.store.book[-1].title'), 'Moby');
      expect(JsonPath.readFrom(json, r'$.store.book[*].author'), ['Nigel', 'Evelyn', 'Herman']);
      expect(JsonPath.readFrom(json, r'$..author'), ['Nigel', 'Evelyn', 'Herman']);
      expect(JsonPath.readFrom(json, r'$.store.book[0,1].title'), ['Sayings', 'Sword']);
      expect(JsonPath.readFrom(json, r'$.store.book[:2].title'), ['Sayings', 'Sword']);
      expect(JsonPath.readFrom(json, r'$.store.book[-1:].title'), ['Moby']);
      expect(JsonPath.readFrom(json, r"$['store']['bicycle']['color']"), 'red');
      expect((JsonPath.readFrom(json, r'$..price') as List).length, 4);
      expect(JsonPath.readFrom(json, r'$.store.book.length()'), 3);
    });

    test('filters', () {
      expect(JsonPath.readFrom(json, r'$.store.book[?(@.price < 9)].title'), ['Sayings', 'Moby']);
      expect(JsonPath.readFrom(json, r"$.store.book[?(@.category == 'fic')].author"), ['Evelyn', 'Herman']);
      expect(JsonPath.readFrom(json, r'$.store.book[?(@.isbn)].title'), ['Sword']);
      expect(JsonPath.readFrom(json, r'$.store.book[?(@.price > 8.95 && @.category == "fic")].title'), ['Sword', 'Moby']);
      expect(JsonPath.readFrom(json, r'$.store.book[?(@.title =~ /^s/i)].title'), ['Sayings', 'Sword']);
      expect(JsonPath.readFrom(json, r'$.store.book[?(@.price < $.expensive)].title'), ['Sayings', 'Moby']);
      expect(JsonPath.readFrom(json, r"$.store.book[?(@.author in ['Nigel','Herman'])].title"), ['Sayings', 'Moby']);
    });

    test('definite paths throw when absent, indefinite give empty lists', () {
      expect(() => JsonPath.readFrom(json, r'$.nothing'), throwsA(isA<PathNotFoundException>()));
      expect(JsonPath.readFrom(json, r'$.store.book[*].nothing'), isEmpty);
    });

    test('AnalyzeByJSonPath rule helpers', () {
      final j = AnalyzeByJSonPath(json);
      expect(j.getString(r'$.name'), 'shop');
      expect(j.getString(r'$.store.book[*].title'), 'Sayings\nSword\nMoby');
      expect(j.getStringList(r'$.store.book[*].author'), ['Nigel', 'Evelyn', 'Herman']);
      expect(j.getString(r'$.store.book[0].author&&$.name'), 'Nigel\nshop');
      expect(j.getString(r'$.missing||$.name'), 'shop');
      expect(j.getString(r'{$.name}-{$.store.bicycle.color}'), 'shop-red');
      expect(j.getList(r'$.store.book')!.length, 3);
      expect(j.getList(r'$.store.book[0].title%%$.store.book[1].title%%$.store.book[2].title')!.length, 3);
      expect(j.getString(r'$.expensive'), '10');
    });
  });

  group('AnalyzeRule', () {
    AnalyzeRule rule([Object? content, String base = 'http://site.example/dir/page.html']) {
      final r = AnalyzeRule(RuleData(), null);
      r.setContent(content ?? page, base);
      r.setRedirectUrl(base);
      return r;
    }

    test('mode detection: default, json, xpath, @css', () async {
      expect(await rule().getString('class.title@text'), 'Book One');
      expect(await rule().getString('//h1/b/text()'), 'One');
      expect(await rule().getString('@XPath://h1/b/text()'), 'One');
      expect(await rule(<String, Object?>{'a': {'b': 5}}).getString(r'$.a.b'), '5');
      expect(await rule('{"a":{"b":"x"}}').getString(r'$.a.b'), 'x');
      expect(await rule('{"a":{"b":"x"}}').getString('@Json:\$.a.b'), 'x');
      expect(await rule().getString('@css:#main > h1@text'), 'Book One');
      expect(await rule().getString('@@class.title@text'), 'Book One');
    });

    test('absolute url resolution with isUrl', () async {
      expect(await rule().getString('class.item.0@tag.a@href', isUrl: true), 'http://site.example/b/1');
      expect(await rule().getString('class.item.2@tag.a@href', isUrl: true), 'http://other.example/b/3');
      expect(await rule().getStringList('class.item@tag.a@href', isUrl: true), ['http://site.example/b/1', 'http://site.example/b/2', 'http://other.example/b/3']);
      expect(await rule().getString('class.nothing@href', isUrl: true), 'http://site.example/dir/page.html');
    });

    test('##regex##replacement###', () async {
      expect(await rule().getString('class.item.0@tag.a@text##irst##IRST'), 'FIRST');
      expect(await rule().getString(r'class.item.0@tag.a@href##/b/(\d)##n=$1'), 'n=1');
      expect(await rule().getString('class.title@text##Book ##'), 'One');
      expect(await rule().getString('class.title@text##o##0###'), '0'); // replaceFirst keeps only the replaced match
      expect(await rule().getStringList('class.item@tag.a@text##i##I'), ['FIrst', 'Second', 'ThIrd']);
    });

    test('@put and @get', () async {
      final r = rule();
      expect(await r.getString('class.title@text@put:{t:class.title@text}'), 'Book One');
      expect(r.get('t'), 'Book One');
      expect(await r.getString('@get:{t}'), 'Book One');
      expect(await r.getString('prefix-@get:{t}-suffix'), 'prefix-Book One-suffix');
      expect(r.get('missing'), '');
      final b = Book(name: 'BName');
      final r2 = AnalyzeRule(b, null)..setContent(page, 'http://x.example/');
      expect(await r2.getString('@get:{bookName}'), 'BName');
      final ch = BookChapter(title: 'Ch1');
      r2.setChapter(ch);
      expect(await r2.getString('@get:{title}'), 'Ch1');
      await r2.getString('class.title@text@put:{k:class.intro@ownText}');
      expect(ch.variableMap['k'], 'Line one Line two tail');
    });

    test('{{ }} templates: rules and JS', () async {
      expect(await rule().getString('{{@@class.title@text}}-{{@@class.item.0@tag.a@text}}'), 'Book One-First');
      expect(await rule().getString('v{{1+2}}x'), 'v3x');
      expect(await rule().getString('{{"a".toUpperCase()}}'), 'A');
      expect(await rule('{"n":"x","m":2}').getString(r'{{$.n}}{{$.m}}'), 'x2');
    });

    test('JS steps: @js: and <js> blocks with result', () async {
      expect(await rule().getString('class.title@text@js:result + "!"'), 'Book One!');
      expect(await rule().getString('class.title@text<js>result.toUpperCase()</js>'), 'BOOK ONE');
      expect(await rule().getString('<js>"static"</js>'), 'static');
      expect(await rule().getString('class.item.0@tag.a@text@js:result.split("").reverse().join("")'), 'tsriF');
      expect(await rule().getString('@js:baseUrl'), 'http://site.example/dir/page.html');
      expect(await rule().getStringList('class.item@tag.a@text@js:result.map(function(x){return x.length})'), ['5', '6', '5']);
      expect((await rule().getString('class.title@text@js:java.md5Encode(result)')).length, 32);
    });

    test('java.* natives from rule JS', () async {
      expect(await rule().getString('@js:java.base64Encode("hello")'), 'aGVsbG8=');
      expect(await rule().getString('@js:java.base64Decode("aGVsbG8=")'), 'hello');
      expect(await rule().getString('@js:java.md5Encode("abc")'), '900150983cd24fb0d6963f7d28e17f72');
      expect(await rule().getString('@js:java.md5Encode16("abc")'), '3cd24fb0d6963f7d');
      expect(await rule().getString('@js:java.sha1Encode("abc")'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(await rule().getString('@js:java.hexEncodeToString("abc")'), '616263');
      expect(await rule().getString('@js:java.urlEncode("a b&c")'), 'a+b%26c');
      expect(await rule().getString('@js:java.t2s("漢字")'), '汉字');
      expect(await rule().getString('@js:java.htmlDecode("&lt;a&gt;")'), '<a>');
      expect(await rule().getString('@js:java.getString("class.title@text")'), 'Book One');
      expect(await rule().getString('@js:java.getStringList("class.item@tag.a@text").length'), '3');
      expect(await rule().getString('@js:java.put("kk","vv"); java.get("kk")'), 'vv');
      expect(await rule().getString('@js:java.toNumChapter("第一百二十三章 x")'), '第123章 x');
      expect(await rule().getString('@js:cache.put("ck", "cv"); cache.get("ck")'), 'cv');
    });

    test('regex all-in-one mode (":" prefix) and \$n groups', () async {
      const text = 'a1:Alice;a2:Bob;a3:Carol';
      final r = rule(text);
      final list = await r.getElements(r':(\w+):(\w+)');
      expect(list.length, 3);
      expect((list[1] as List)[2], 'Bob');
      r.setContent(list[2]);
      expect(await r.getString(r'name=$2 id=$1'), 'name=Carol id=a3');
    });

    test('getElements for lists and item rules', () async {
      final r = rule();
      final items = await r.getElements('class.item');
      expect(items.length, 3);
      r.setContent(items[1]);
      expect(await r.getString('tag.a@text'), 'Second');
      expect(await r.getString('tag.a@href', isUrl: true), 'http://site.example/b/2');
      expect(await r.getString('.tag@text'), 'b');
      final jr = rule({
        'data': {
          'list': [
            {'n': 'x', 'u': '/1'},
            {'n': 'y', 'u': '/2'}
          ]
        }
      });
      final jitems = await jr.getElements(r'$.data.list[*]');
      expect(jitems.length, 2);
      jr.setContent(jitems[1]);
      expect(await jr.getString(r'$.n'), 'y');
      expect(await jr.getString(r'$.u', isUrl: true), 'http://site.example/2');
      final xr = rule();
      final xi = await xr.getElements('//li');
      xr.setContent(xi[2]);
      expect(await xr.getString('//a/text()'), 'Third');
      expect(await xr.getString('./span/text()'), 'c');
    });

    test('getElement and init narrowing', () async {
      final r = rule();
      final e = await r.getElement('id.main@class.list');
      expect(e, isNotNull);
      r.setContent(e!);
      expect(await r.getStringList('tag.a@text'), ['First', 'Second', 'Third']);
    });

    test('entities are decoded in results', () async {
      expect(await rule('<p>a &amp; b &lt; c &#65;</p>').getString('tag.p@text'), 'a & b < c A');
    });

    test('network utils', () {
      expect(NetworkUtils.getAbsoluteURL('http://a.com/x/y.html', '../z'), 'http://a.com/z');
      expect(NetworkUtils.getAbsoluteURL('http://a.com/x/y.html', '//b.com/q'), 'http://b.com/q');
      expect(NetworkUtils.getAbsoluteURL('http://a.com/x/y.html', '?p=2'), 'http://a.com/x/y.html?p=2');
      expect(NetworkUtils.getAbsoluteURL('http://a.com/x,{"method":"POST"}', 'k'), 'http://a.com/k');
      expect(NetworkUtils.getBaseUrl('https://a.com:8080/p?q'), 'https://a.com:8080');
      expect(NetworkUtils.getSubDomain('http://m.novel.example.com/x'), 'example.com');
      expect(NetworkUtils.getSubDomain('http://a.b.example.com.cn/x'), 'example.com.cn');
      expect(NetworkUtils.hasUrlEncoded('%E4%BD%A0'), isTrue);
      expect(NetworkUtils.hasUrlEncoded('你好'), isFalse);
    });
  });
}
