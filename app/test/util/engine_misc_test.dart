import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/rssapi.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/util/chinese_utils.dart';
import 'package:newread/util/cookiemanger.dart';
import 'package:newread/util/format.dart';
import 'package:newread/util/html/entities.dart';
import 'package:newread/util/json.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/legado/html_formatter.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/legado/js_runtime.dart';
import 'package:newread/util/legado/set_cookie_parser.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_rule.dart';
import 'package:newread/util/webbook/analyze_rule/js_encode_utils.dart';
import 'package:newread/util/webbook/analyze_rule/rule_data.dart';
import 'package:newread/util/webbook/model/book.dart';
import 'package:newread/util/webbook/model/book_source.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

import 'fake_site.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late FakeSite site;

  setUpAll(() async {
    JsEngines.useDart();
    site = await FakeSite.start();
  });
  tearDownAll(() => site.close());
  setUp(() {
    CookieStore.resetForTests();
    CacheManager.resetForTests();
  });

  group('crypto natives', () {
    test('known-answer vectors (AES, DES, 3DES) and round trips', () {
      final zero16 = List<int>.filled(16, 0);
      expect(hex(JsEncodeUtils.symmetric(transformation: 'AES/ECB/NoPadding', key: zero16, data: zero16, encrypt: true)), '66e94bd4ef8a2c3b884cfa59ca342b2e');
      final desKey = [0x13, 0x34, 0x57, 0x79, 0x9b, 0xbc, 0xdf, 0xf1];
      final desData = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
      expect(hex(JsEncodeUtils.symmetric(transformation: 'DES/ECB/NoPadding', key: desKey, data: desData, encrypt: true)), '85e813540f0ab405');
      expect(hex(JsEncodeUtils.symmetric(transformation: 'DESede/ECB/NoPadding', key: [...desKey, ...desKey, ...desKey], data: desData, encrypt: true)), '85e813540f0ab405');
      for (final t in ['AES/CBC/PKCS5Padding', 'AES/ECB/PKCS7Padding', 'AES/CFB/NoPadding', 'AES/CTR/NoPadding', 'AES/CBC/ZeroPadding']) {
        final key = utf8.encode('1234567890abcdef');
        final iv = utf8.encode('fedcba0987654321');
        final enc = JsEncodeUtils.symmetric(transformation: t, key: key, iv: iv, data: utf8.encode('你好, legado!'), encrypt: true);
        final dec = JsEncodeUtils.symmetric(transformation: t, key: key, iv: iv, data: enc, encrypt: false);
        expect(utf8.decode(dec), '你好, legado!', reason: t);
      }
    });

    test('java.* AES/DES helpers and createSymmetricCrypto from JS', () async {
      final r = AnalyzeRule(RuleData())..setContent('x');
      final enc = await r.getString('@js:java.aesEncodeToBase64String("secret", "1234567890abcdef", "AES/CBC/PKCS5Padding", "fedcba0987654321")');
      expect(await r.getString('@js:java.aesBase64DecodeToString("$enc", "1234567890abcdef", "AES/CBC/PKCS5Padding", "fedcba0987654321")'), 'secret');
      expect(await r.getString('@js:java.aesDecodeToString("$enc", "1234567890abcdef", "AES/CBC/PKCS5Padding", "fedcba0987654321")'), 'secret');
      final des = await r.getString('@js:java.desEncodeToBase64String("abc", "12345678", "DES/ECB/PKCS5Padding", "")');
      expect(await r.getString('@js:java.desBase64DecodeToString("$des", "12345678", "DES/ECB/PKCS5Padding", "")'), 'abc');
      final t3 = await r.getString('@js:java.tripleDESEncodeBase64Str("abc", "123456789012345678901234", "CBC", "PKCS5Padding", "12345678")');
      expect(await r.getString('@js:java.tripleDESDecodeStr("$t3", "123456789012345678901234", "CBC", "PKCS5Padding", "12345678")'), 'abc');
      expect(
          await r.getString(
              '@js:var c = java.createSymmetricCrypto("AES/ECB/PKCS5Padding", "1234567890abcdef"); c.decryptStr(c.encryptBase64("hutool"))'),
          'hutool');
      expect(await r.getString('@js:java.HMacHex("data", "HmacSHA256", "key")'), '5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0');
      expect(await r.getString('@js:java.digestHex("abc", "SHA-256")'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await r.getString('@js:java.encodeURI("你", "gbk")'), '%C4%E3');
      expect(await r.getString('@js:java.utf8ToGbkUrlEncoded("你")'), '%C4%E3');
      expect(await r.getString('@js:java.bytesToStr(java.strToBytes("你好", "gbk"), "gbk")'), '你好');
      expect(await r.getString('@js:java.base64DecodeToByteArray("AQID").join(",")'), '1,2,3');
      expect(await r.getString('@js:java.timeFormatUTC(0, "yyyy-MM-dd HH:mm", 8)'), '1970-01-01 08:00');
      expect(await r.getString('@js:java.randomUUID().length'), '36');
      expect(await r.getString('@js:java.toURL("http://a.com:8080/p/q?x=1#h").pathname'), '/p/q');
    });
  });

  group('network natives through the replay runner', () {
    test('java.ajax, java.connect, java.post, java.get(url, headers) from rule JS', () async {
      final source = BookSource(bookSourceUrl: site.base);
      final r = AnalyzeRule(Book(), source)..setContent('x', site.base);
      expect(await r.getString('@js:java.ajax("${site.base}/book/1").indexOf("斗破苍穹") > 0'), 'true');
      expect(await r.getString('@js:var a = java.connect("${site.base}/book/1"); a.code() + ":" + a.url()'), '200:${site.base}/book/1');
      expect(await r.getString('@js:JSON.parse(java.post("${site.base}/echo", "a=1", {"X-P":"q"}).body()).headers["x-p"]'), 'q');
      expect(await r.getString('@js:JSON.parse(java.get("${site.base}/echo?z=2", {}).body()).query'), 'z=2');
      expect(await r.getString('@js:java.ajax("${site.base}/book/1") == java.ajax("${site.base}/book/1")'), 'true');
      // a page fetched in JS can be parsed with the rule engine from JS as well
      expect(await r.getString('@js:java.setContent(java.ajax("${site.base}/book/1")); java.getString("id.name@text")'), '斗破苍穹');
      // cookies set by the site are visible to cookie.* and java.getCookie
      await r.getString('@js:java.ajax("${site.base}/cookie/set")');
      expect(await r.getString('@js:cookie.getKey("${site.base}", "sid")'), 'abc123');
      expect(await r.getString('@js:java.getCookie("${site.base}", "theme")'), 'dark');
      expect(await r.getString('@js:java.ajax("${site.base}/cookie/check").substring(0, 3)'), 'ok:');
    });

    test('java.log goes to the log sink once per evaluation', () async {
      final lines = <String>[];
      JsScriptRunner.logSink = lines.add;
      final r = AnalyzeRule(RuleData())..setContent('x', site.base);
      await r.getString('@js:java.log("before"); java.ajax("${site.base}/book/1"); java.log("after"); 1');
      JsScriptRunner.logSink = null;
      expect(lines, ['before', 'after']);
    });

    test('FakeJsRuntime can stand in for scripted answers', () async {
      JsEngines.use(FakeJsRuntime(scripts: {'magic()': (b) => 'from-fake:${b.values['result']}'}));
      try {
        final r = AnalyzeRule(RuleData())..setContent('<p>v</p>');
        expect(await r.getString('tag.p@text@js:magic()'), 'from-fake:v');
      } finally {
        JsEngines.useDart();
      }
    });
  });

  group('text helpers', () {
    test('Chinese conversion (tables of the original)', () {
      expect(ChineseUtils.toSimplified('漢字與繁體'), '汉字与繁体');
      expect(ChineseUtils.toTraditional('简体中文'), '簡體中文');
      expect(ChineseUtils.toTraditional('理发'), '理髮'); // phrase table beats the character table (发 -> 發)
      expect(ChineseUtils.toSimplified('一目瞭然'), '一目了然');
      expect(ChineseUtils.toSimplified('abc 123'), 'abc 123');
    });

    test('Format helpers', () {
      expect(Format.toNumChapter('第一百二十三章 归来'), '第123章 归来');
      expect(Format.toNumChapter('第两千零五回'), '第2005回');
      expect(Format.toNumChapter('第十章'), '第10章');
      expect(Format.toNumChapter('第一零二四章'), '第1024章');
      expect(Format.toNumChapter('序章'), '序章');
      expect(Format.wordCountFormat('1234'), '1234字');
      expect(Format.wordCountFormat('1234567'), '123.5万字');
      expect(Format.wordCountFormat('20000'), '2万字');
      expect(Format.wordCountFormat('约20万字'), '约20万字');
      expect(Format.isTrue('true'), isTrue);
      expect(Format.isTrue('1'), isTrue);
      expect(Format.isTrue('卷'), isTrue);
      expect(Format.isTrue('false'), isFalse);
      expect(Format.isTrue('0'), isFalse);
      expect(Format.isTrue(''), isFalse);
      expect(Format.isTrue(null), isFalse);
    });

    test('HtmlFormatter and entities', () {
      expect(HtmlFormatter.format('<p>a</p><p>b</p>'), '　　a\n　　b');
      expect(HtmlFormatter.format('one<br/>two<!-- x --><span>three</span>'), 'one\n　　twothree');
      expect(HtmlFormatter.formatKeepImg('<div>t<img class="x" src="/a.png"></div>', redirectUrl: 'http://h.example/p/'), '　　t<img src="http://h.example/a.png">');
      expect(htmlDecode('&lt;b&gt; &amp;amp; &#x4F60;&#22909; &nbsp;&unknown;'), '<b> &amp; 你好  &unknown;');
      expect(htmlEncode('<a href="x">'), '&lt;a href=&quot;x&quot;&gt;');
    });

    test('lenient JSON (Gson style)', () {
      expect(jsonutil.tryDecodeLenient("{'a':1, b:'x', c:[1,2,], // c\n d:true}"), {'a': 1, 'b': 'x', 'c': [1, 2], 'd': true});
      expect(jsonutil.tryDecodeLenient('{k:class.title@text##a}'), {'k': 'class.title@text##a'});
      expect(jsonutil.tryDecodeLenient('not json'), 'not');
    });
  });

  group('cookies', () {
    test('Set-Cookie parsing and the store', () {
      final c = SetCookieParser.parse('sid=abc; Path=/; Domain=.example.com; Max-Age=60; HttpOnly; Secure')!;
      expect(c.name, 'sid');
      expect(c.domain, 'example.com');
      expect(c.httpOnly && c.secure, isTrue);
      expect(c.isDeletion, isFalse);
      expect(SetCookieParser.parse('x=; Max-Age=0')!.isDeletion, isTrue);
      expect(SetCookieParser.parse('x=1; Expires=Thu, 01 Jan 1970 00:00:00 GMT')!.isDeletion, isTrue);
      CookieStore.setCookie('http://a.example.com/x', 'a=1; b=2');
      expect(CookieStore.getCookie('http://www.example.com/'), 'a=1; b=2'); // same registrable domain
      CookieStore.replaceCookie('http://a.example.com', 'b=3;c=4');
      expect(CookieStore.cookieToMap(CookieStore.getCookie('http://example.com')), {'a': '1', 'b': '3', 'c': '4'});
      CookieStore.saveFromResponse('http://example.com', ['a=; Max-Age=0']);
      expect(CookieStore.getKey('http://example.com', 'a'), '');
      CookieStore.removeCookie('http://example.com');
      expect(CookieStore.getCookie('http://example.com'), '');
    });

    test('MyCookieManger and the WebView hooks', () async {
      await MyCookieManger.set('http://w.example/', 'k=v');
      expect(await MyCookieManger.get('http://w.example/a'), 'k=v');
      String? pushed;
      WebviewCookieManger.pushToWebView = (u, c) async => pushed = c;
      WebviewCookieManger.pullFromWebView = (u) async => 'w=1';
      await WebviewCookieManger.push('http://w.example/');
      await WebviewCookieManger.pull('http://w.example/');
      expect(pushed, 'k=v');
      expect(CookieStore.getKey('http://w.example', 'w'), '1');
      WebviewCookieManger.pushToWebView = null;
      WebviewCookieManger.pullFromWebView = null;
      await MyCookieManger.delete('http://w.example/');
      expect(await MyCookieManger.get('http://w.example/'), '');
    });
  });

  group('source import and debug', () {
    test('importFromUrl and parseSources', () async {
      final sources = await SourceApi.importFromUrl('${site.base}/source.json');
      expect(sources.map((s) => s.bookSourceName), ['HTML站', 'JSON站']);
      expect(sources.first.getSearchRule().bookList, 'class.book');
      // round trip keeps unknown keys
      final again = SourceApi.parseSources(jsonEncode([
        {...sources.first.toJson(), 'unknownKey': 7}
      ]));
      expect(again.first.toJson()['unknownKey'], 7);
      expect(again.first.toJson()['ruleToc']['nextTocUrl'], 'id.next@href');
      expect(RssRunapi.parseSources('{"sourceUrl":"u","sourceName":"n"}').single.sourceName, 'n');
    });

    test('debug runs the whole chain from a keyword, a book url, ++toc and --content', () async {
      final source = BookSource.fromJsonString(site.sourceJson('source_html.json'));
      final lines = <String>[];
      final log = await SourceApi.debug(source, '斗破', onLine: lines.add);
      expect(log.lines.any((l) => l.contains('︽搜索页解析完成 2')), isTrue);
      expect(log.lines.any((l) => l.contains('︽目录页解析完成 5')), isTrue);
      expect(log.lines.any((l) => l.contains('︽正文页解析完成')), isTrue);
      expect(lines.length, log.lines.length);
      final byUrl = await SourceApi.debug(source, '${site.base}/book/1');
      expect(byUrl.lines.any((l) => l.contains('︽详情页解析完成')), isTrue);
      final toc = await SourceApi.debug(source, '++${site.base}/book/1/toc');
      expect(toc.lines.any((l) => l.contains('︽目录页解析完成')), isTrue);
      final content = await SourceApi.debug(source, '--${site.base}/chapter/2');
      expect(content.lines.any((l) => l.contains('︽正文页解析完成')), isTrue);
      final explore = await SourceApi.debug(source, '热门::/html/search?q=hot&page=1');
      expect(explore.lines.any((l) => l.contains('︽发现页解析完成 2')), isTrue);
      final bad = await SourceApi.debug(BookSource(bookSourceUrl: site.base), 'x');
      expect(bad.lines.last, contains('error: 搜索url不能为空'));
    });

    test('decodeImage leaves bytes alone without a rule', () async {
      final out = await SourceApi.decodeImage(BookSource(bookSourceUrl: site.base), Book(), null, 'u', Uint8List.fromList([7]));
      expect(out, [7]);
    });
  });
}
