// A demo book site served from 127.0.0.1 inside the integration test (no internet on the CI simulator): one search page, an explore
// list, two books with a table of contents and chapter pages. The text is written for this test. The book source uses CSS rules plus
// one `@js:` rule so the JavaScript engine of the device (JavaScriptCore via flutter_js on iOS) is exercised too.
import 'dart:convert';
import 'dart:io';

class DemoSite {
  final HttpServer server;
  final List<String> requests = [];
  DemoSite._(this.server);

  String get base => 'http://127.0.0.1:${server.port}';

  static Future<DemoSite> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = DemoSite._(s);
    s.listen(site._handle);
    return site;
  }

  Future<void> close() => server.close(force: true);

  static const books = [
    (id: 1, name: '星河旅人', author: '林间', kind: '科幻', intro: '一艘迷航的货船，一位只会修理钟表的船员，和一张通往群星尽头的旧地图。'),
    (id: 2, name: '山城旧事', author: '青禾', kind: '都市', intro: '雾气终年不散的山城里，一家开了五十年的面馆藏着三代人的秘密。'),
  ];

  static const chapterCount = 12;

  /// The book source (Legado JSON) for this site.
  Map<String, dynamic> source() => {
        'bookSourceName': '演示书源',
        'bookSourceUrl': base,
        'bookSourceGroup': '演示',
        'bookSourceType': 0,
        'enabled': true,
        'enabledExplore': true,
        'searchUrl': '/search?q={{key}}&page={{page}}',
        'exploreUrl': '热门::/explore?page={{page}}',
        'ruleSearch': {
          'bookList': 'class.book',
          'name': 'class.name@text',
          'author': 'class.author@text##作者：',
          'bookUrl': 'class.name@href',
          'kind': 'class.kind@text',
          'intro': 'class.desc@text',
        },
        'ruleExplore': {
          'bookList': 'class.book',
          'name': 'class.name@text',
          'author': 'class.author@text##作者：',
          'bookUrl': 'class.name@href',
          'kind': 'class.kind@text',
        },
        'ruleBookInfo': {
          'name': 'id.name@text',
          'author': 'class.author@text##作者：',
          'kind': 'class.kind@text',
          'intro': 'id.intro@text',
          'lastChapter': 'id.last@text##最新：',
          'tocUrl': 'id.toc@href',
        },
        'ruleToc': {
          'chapterList': 'id.chapters@tag.li',
          'chapterName': 'tag.a@text',
          'chapterUrl': 'tag.a@href',
        },
        'ruleContent': {
          // the @js: step runs on the device's JS engine: it strips the site's "广告" lines
          'content': r'id.content@html@js:result.replace(/<p class="ad">[^<]*<\/p>/g, "")',
        },
      };

  String sourceJson() => jsonEncode([source()]);

  static String _page(String body) =>
      '<!DOCTYPE html><html><head><meta charset="utf-8"><title>演示书站</title></head><body>$body</body></html>';

  static String _item(({int id, String name, String author, String kind, String intro}) b) =>
      '<div class="book"><a class="name" href="/book/${b.id}">${b.name}</a><span class="author">作者：${b.author}</span>'
      '<span class="kind">${b.kind}</span><p class="desc">${b.intro}</p></div>';

  static String chapterTitle(int n) => '第${n}章 ${_titles[(n - 1) % _titles.length]}';

  static const _titles = ['启程', '旧地图', '夜航', '无声的灯塔', '雾中来客', '钟表匠', '星图', '远方', '归途', '风暴', '残光', '尽头'];

  static const _sentences = [
    '风从舷窗的缝隙里钻进来，带着一点铁锈和海盐的味道。',
    '他把那只停摆的怀表放在掌心，听不到任何声音，却总觉得它还在走。',
    '远处的灯一盏接一盏地亮起，像有人在黑暗里慢慢写下一行字。',
    '没有人知道这条航线通向哪里，地图的边角早已被反复摩挲得发白。',
    '她说，等雾散了，我们就能看见城市的另一面。',
    '桌上的茶已经凉了，窗外的雨却越下越大。',
    '他第一次意识到，所谓远方，不过是另一个人的故乡。',
    '甲板上很安静，只有缆绳偶尔发出轻微的吱呀声。',
  ];

  static String chapterText(int book, int n) {
    final b = StringBuffer();
    for (var p = 0; p < 18; p++) {
      final s1 = _sentences[(n * 3 + p + book) % _sentences.length];
      final s2 = _sentences[(n + p * 5 + book * 2) % _sentences.length];
      b.write('<p>$s1$s2</p>');
      if (p == 6) b.write('<p class="ad">广告：本站演示内容，请勿当真。</p>');
    }
    return b.toString();
  }

  void _send(HttpRequest req, String html) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..add(utf8.encode(html));
    req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    requests.add(req.uri.toString());
    final seg = req.uri.pathSegments;
    if (req.uri.path == '/search' || req.uri.path == '/explore') {
      final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
      final q = req.uri.queryParameters['q'] ?? '';
      final hits = [for (final b in books) if (req.uri.path == '/explore' || q.isEmpty || b.name.contains(q) || b.author.contains(q) || q == '演示') b];
      return _send(req, _page(page > 1 ? '' : hits.map(_item).join()));
    }
    if (seg.length == 2 && seg[0] == 'book') {
      final b = books.firstWhere((e) => '${e.id}' == seg[1], orElse: () => books.first);
      return _send(
          req,
          _page('<h1 id="name">${b.name}</h1><span class="author">作者：${b.author}</span><span class="kind">${b.kind}</span>'
              '<div id="intro">${b.intro}</div><div id="last">最新：${chapterTitle(chapterCount)}</div>'
              '<a id="toc" href="/book/${b.id}/toc">目录</a>'));
    }
    if (seg.length == 3 && seg[0] == 'book' && seg[2] == 'toc') {
      final items = [for (var n = 1; n <= chapterCount; n++) '<li><a href="/chapter/${seg[1]}/$n">${chapterTitle(n)}</a></li>'];
      return _send(req, _page('<ul id="chapters">${items.join()}</ul>'));
    }
    if (seg.length == 3 && seg[0] == 'chapter') {
      final book = int.tryParse(seg[1]) ?? 1;
      final n = int.tryParse(seg[2]) ?? 1;
      return _send(req, _page('<h2 class="ct">${chapterTitle(n)}</h2><div id="content">${chapterText(book, n)}</div>'));
    }
    req.response.statusCode = 404;
    await req.response.close();
  }
}
