import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/http.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/source/qhttp.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_url.dart';
import 'package:newread/util/webbook/analyze_rule/rule_data.dart';
import 'package:newread/util/webbook/model/book_source.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

import 'fake_site.dart';

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
    site.requests.clear();
    site.hits.clear();
  });

  group('charset handling', () {
    test('explicit charset, Content-Type, BOM, meta, utf-8 validity, gbk fallback', () {
      final gbkBytes = gbk.encode('你好，世界');
      expect(AppHttp.decodeBody(gbkBytes, charset: 'gbk'), '你好，世界');
      expect(AppHttp.decodeBody(gbkBytes, contentType: 'text/html; charset=GB2312'), '你好，世界');
      expect(AppHttp.decodeBody(gbkBytes, contentType: 'text/html; charset="gbk"'), '你好，世界');
      expect(AppHttp.decodeBody([0xef, 0xbb, 0xbf, ...utf8.encode('bom 文本')]), 'bom 文本');
      final meta = gbk.encode('<html><head><meta charset="gbk"></head><body>你好</body></html>');
      expect(AppHttp.decodeBody(meta), contains('你好'));
      final metaHttpEquiv = gbk.encode('<meta http-equiv="Content-Type" content="text/html; charset=gb2312">汉字');
      expect(AppHttp.decodeBody(metaHttpEquiv), contains('汉字'));
      expect(AppHttp.decodeBody(utf8.encode('plain utf8 中文')), 'plain utf8 中文');
      expect(AppHttp.decodeBody(gbk.encode('没有声明编码的 GBK 页面')), '没有声明编码的 GBK 页面'); // not valid UTF-8 -> GBK
      expect(AppHttp.decodeBody(const []), '');
      expect(AppHttp.decodeBody(latin1.encode('café'), charset: 'iso-8859-1'), 'café');
    });

    test('percent-encoding in a charset', () {
      expect(AppHttp.encodeWith('你', 'gbk'), [0xc4, 0xe3]);
      expect(AppHttp.encodeWith('你', 'utf-8'), [0xe4, 0xbd, 0xa0]);
    });
  });

  group('transport against the local site', () {
    test('GBK page served with only a meta tag and with a header charset', () async {
      final r1 = await AppHttp.send(HttpRequest(url: '${site.base}/gbk/header'));
      expect(AppHttp.decodeBody(r1.bodyBytes, contentType: r1.contentType), contains('你好，世界'));
      final r2 = await AppHttp.send(HttpRequest(url: '${site.base}/gbk/search?wd=%C4%E3'));
      final text = AppHttp.decodeBody(r2.bodyBytes, contentType: r2.contentType);
      expect(text, contains('斗破苍穹'));
      expect(text, contains('你')); // echoed keyword decoded from GBK bytes on the server
    });

    test('redirect chain, final url and POST->GET conversion', () async {
      final r = await AppHttp.send(HttpRequest(url: '${site.base}/redir1'));
      expect(r.statusCode, 200);
      expect(r.url, '${site.base}/book/1');
      expect(utf8.decode(r.bodyBytes), contains('斗破苍穹'));
      final p = await AppHttp.send(HttpRequest(url: '${site.base}/post-redir', method: 'POST', body: 'a=1'));
      expect(jsonDecode(utf8.decode(p.bodyBytes))['method'], 'GET');
      final nf = await AppHttp.send(HttpRequest(url: '${site.base}/redir1', followRedirects: false));
      expect(nf.statusCode, 302);
    });

    test('cookies are stored from Set-Cookie and sent back', () async {
      final denied = await AppHttp.send(HttpRequest(url: '${site.base}/cookie/check'));
      expect(denied.statusCode, 403);
      await AppHttp.send(HttpRequest(url: '${site.base}/cookie/set'));
      expect(CookieStore.getKey(site.base, 'sid'), 'abc123');
      expect(CookieStore.getKey(site.base, 'theme'), 'dark');
      final ok = await AppHttp.send(HttpRequest(url: '${site.base}/cookie/check'));
      expect(utf8.decode(ok.bodyBytes), startsWith('ok:'));
      // a header cookie is merged with the stored ones
      final merged = await AppHttp.send(HttpRequest(url: '${site.base}/echo', headers: {'Cookie': 'extra=1'}));
      final h = jsonDecode(utf8.decode(merged.bodyBytes))['headers'] as Map;
      expect(h['cookie'], allOf(contains('sid=abc123'), contains('extra=1')));
      // cookie jar off: nothing is sent
      final off = await AppHttp.send(HttpRequest(url: '${site.base}/echo', useCookieJar: false));
      expect((jsonDecode(utf8.decode(off.bodyBytes))['headers'] as Map).containsKey('cookie'), isFalse);
    });

    test('gzip bodies are decompressed, POST defaults, UA and custom headers', () async {
      final g = await AppHttp.send(HttpRequest(url: '${site.base}/gzip'));
      expect(AppHttp.decodeBody(g.bodyBytes, contentType: g.contentType), '压缩内容 compressed');
      final e = await AppHttp.send(HttpRequest(url: '${site.base}/echo?x=1', method: 'POST', body: 'k=v&n=2', headers: {'X-A': 'b'}));
      final j = jsonDecode(utf8.decode(e.bodyBytes)) as Map;
      expect(j['method'], 'POST');
      expect(j['body'], 'k=v&n=2');
      expect(j['query'], 'x=1');
      expect((j['headers'] as Map)['content-type'], startsWith('application/x-www-form-urlencoded'));
      expect((j['headers'] as Map)['x-a'], 'b');
      expect((j['headers'] as Map)['user-agent'], AppHttp.userAgent);
      final js = await AppHttp.send(HttpRequest(url: '${site.base}/echo', method: 'POST', body: '{"a":1}'));
      expect(((jsonDecode(utf8.decode(js.bodyBytes)) as Map)['headers'] as Map)['content-type'], startsWith('application/json'));
    });

    test('retry on server errors and failure messages', () async {
      final bad = await AppHttp.send(HttpRequest(url: '${site.base}/flaky'));
      expect(bad.statusCode, 500);
      site.hits.clear();
      final ok = await AppHttp.send(HttpRequest(url: '${site.base}/flaky', retry: 3));
      expect(utf8.decode(ok.bodyBytes), 'recovered');
      expect(
          () => AppHttp.send(const HttpRequest(url: 'http://127.0.0.1:1/', timeout: Duration(seconds: 2))),
          throwsA(isA<HttpFailure>()));
    });

    test('binary body is untouched, HEAD works', () async {
      final b = await AppHttp.send(HttpRequest(url: '${site.base}/bin'));
      expect(b.bodyBytes, [0, 1, 2, 250, 255]);
      final h = await AppHttp.send(HttpRequest(url: '${site.base}/book/1', method: 'HEAD'));
      expect(h.statusCode, 200);
      expect(h.bodyBytes, isEmpty);
    });

    test('QHttp map contract', () async {
      final r = await QHttp.get({'url': '${site.base}/book/1', 'header': {'X-Q': '1'}, 'move': true});
      expect(r['success'], true);
      expect(r['response'], contains('斗破苍穹'));
      expect(r['currentUrl'], '${site.base}/book/1');
      final p = await QHttp.post({'url': '${site.base}/echo', 'body': 'a=b'});
      expect(jsonDecode(p['response'] as String)['body'], 'a=b');
      final f = await QHttp.get({'url': '${site.base}/missing'});
      expect(f['success'], false);
      final x = await QHttp.get({'url': 'http://127.0.0.1:1/', 'timeout': 1500});
      expect(x['success'], false);
      expect(x['error'], isNotEmpty);
    });
  });

  group('AnalyzeUrl', () {
    Future<AnalyzeUrl> au(String rule, {String? key, int? page, Map<String, String>? headers, String? base}) =>
        AnalyzeUrl.create(rule, key: key, page: page, baseUrl: base ?? site.base, ruleData: RuleData(), headerMapF: headers);

    test('{{key}} and {{page}} templates and arithmetic', () async {
      expect((await au('/s?q={{key}}&p={{page}}', key: 'abc', page: 3)).url, '${site.base}/s?q={{key}}&p={{page}}'.replaceAll('{{key}}', 'abc').replaceAll('{{page}}', '3'));
      expect((await au('/s?o={{(page-1)*20}}', page: 3)).url, '${site.base}/s?o=40');
      expect((await au('/s?o={{page+1}}', page: 1)).url, '${site.base}/s?o=2');
      expect((await au('/s?v={{1+1}}-{{"a"+"b"}}', page: 1)).url, '${site.base}/s?v=2-ab');
    });

    test('<a,b,c> page lists', () async {
      expect((await au('/list<,_2,_3>.html', page: 1)).url, '${site.base}/list.html');
      expect((await au('/list<,_2,_3>.html', page: 2)).url, '${site.base}/list_2.html');
      expect((await au('/list<,_2,_3>.html', page: 9)).url, '${site.base}/list_3.html');
    });

    test('options: lenient JSON, POST body to form fields, headers, retry, type', () async {
      final a = await au("/post,{'method':'POST','body':'k={{key}}&x=1','headers':{'X-H':'v'},'retry':2,'type':'png'}", key: '你 好');
      expect(a.method, RequestMethod.post);
      expect(a.retry, 2);
      expect(a.type, 'png');
      expect(a.headerMap['X-H'], 'v');
      expect(a.fieldMap['k'], '%E4%BD%A0+%E5%A5%BD'); // utf-8, URLEncoder style
      expect(a.requestBody, 'k=%E4%BD%A0+%E5%A5%BD&x=1');
      final b = await au('/p,{"method":"POST","body":{"a":1},"headers":"{\\"A\\":\\"B\\"}"}');
      expect(b.body, '{"a":1}');
      expect(b.headerMap['A'], 'B');
      expect(b.fieldMap, isEmpty); // JSON bodies are sent as they are
      expect(b.requestBody, '{"a":1}');
    });

    test('charset option encodes query values (GBK, escape)', () async {
      final a = await au("/gbk/search?wd={{key}},{'charset':'gbk'}", key: '你');
      expect(a.requestUrl, '${site.base}/gbk/search?wd=%C4%E3');
      final e = await au("/s?w={{key}},{'charset':'escape'}", key: '你a');
      expect(e.fieldMap['w'], '%u4F60a');
      // already percent-encoded values are not encoded twice
      final d = await au('/s?w=%E4%BD%A0');
      expect(d.fieldMap['w'], '%E4%BD%A0');
    });

    test('@js: and <js> url rules, @result, js option', () async {
      expect((await au('@js:"/js?k=" + key', key: 'q')).url, '${site.base}/js?k=q');
      expect((await au('/base<js>result + "/appended"</js>')).url, '${site.base}/base/appended');
      expect((await au('/p<js>result + "?z=1"</js>')).url, '${site.base}/p?z=1');
      final j = await au("/a,{'js':'result + \"?added=1\"'}");
      expect(j.url, '${site.base}/a?added=1');
    });

    test('absolute url with baseUrl that carries options', () async {
      final a = await au('rel/path', base: '${site.base}/dir/,{"x":1}');
      expect(a.url, '${site.base}/dir/rel/path');
    });

    test('real requests: GET fields, POST form, headers from source, retry', () async {
      final source = BookSource.fromJsonString(site.sourceJson('source_html.json'));
      final get = await AnalyzeUrl.create('/html/search?q={{key}}&page={{page}}', key: '斗破', page: 2, baseUrl: source.bookSourceUrl, source: source, headerMapF: await source.getHeaderMap(true));
      final res = await get.getStrResponse();
      expect(res.body, contains('斗破|p2|header-ok'));
      final post = await AnalyzeUrl.create("/html/search_post,{'method':'POST','body':'keyword={{key}}'}", key: '武', baseUrl: site.base);
      final pr = await post.getStrResponse();
      expect(pr.body, contains('keyword=%E6%AD%A6|application/x-www-form-urlencoded'));
      final hex = await AnalyzeUrl.create("/bin,{'type':'bin'}", baseUrl: site.base);
      expect((await hex.getStrResponse()).body, '000102faff');
      final gbkUrl = await AnalyzeUrl.create("/gbk/search?wd={{key}},{'charset':'gbk'}", key: '森', baseUrl: site.base);
      expect((await gbkUrl.getStrResponse()).body, contains('森'));
    });

    test('concurrentRate spaces requests', () async {
      final s = BookSource(bookSourceUrl: site.base, concurrentRate: '150');
      final sw = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        final a = await AnalyzeUrl.create('/book/1', baseUrl: site.base, source: s);
        await a.getStrResponse();
      }
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(280));
    });
  });

  group('source header JS and login storage', () {
    test('header can be JS, a user agent is always present, login header merges', () async {
      final s = BookSource(bookSourceUrl: 'http://hdr.example', header: '@js:JSON.stringify({"X-A": "js-" + 1})');
      final h = await s.getHeaderMap(true);
      expect(h['X-A'], 'js-1');
      expect(h['User-Agent'], AppHttp.userAgent);
      s.putLoginHeader('{"Authorization":"Bearer t"}');
      expect((await s.getHeaderMap(true))['Authorization'], 'Bearer t');
      expect((await s.getHeaderMap())['Authorization'], isNull);
      s.putLoginInfo('{"user":"u"}');
      expect(s.getLoginInfoMap()['user'], 'u');
      s.setVariable('v1');
      expect(s.getVariable(), 'v1');
      s.put('k', 'x');
      expect(s.get('k'), 'x');
    });
  });
}
