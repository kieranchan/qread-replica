import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/http.dart';
import 'package:newread/util/legado/cjk_charsets.dart';

List<int> hex(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

void main() {
  // expected bytes from Python: 'xxx'.encode('cp950' / 'gb18030')
  test('Big5 (cp950) decodes and encodes', () {
    final bytes = hex('c163c5e9a4a4a4e5b4fab8d5a141a3e16f6b');
    expect(CjkCharsets.decodeBig5(bytes), '繁體中文測試，€ok');
    expect(CjkCharsets.encodeBig5('繁體中文測試，€ok'), bytes);
    expect(AppHttp.decodeWith(bytes, 'Big5'), '繁體中文測試，€ok');
    expect(AppHttp.decodeBody(bytes, contentType: 'text/html; charset=big5'), '繁體中文測試，€ok');
    // a broken pair does not swallow the ASCII byte after it
    expect(CjkCharsets.decodeBig5([0xA4, 0x20, 0x41]), '� A');
  });

  test('GB18030 four-byte sequences (BMP ranges and supplementary planes)', () {
    final bytes = hex('61628130843695328236d6d0cec48135f437a2e3813081308431a439');
    const text = 'ab¥𠀀中文ḿ€\u0080￿';
    expect(CjkCharsets.decodeGb18030(bytes), text);
    expect(CjkCharsets.encodeGb18030(text), bytes);
    final more = hex('a8a68139ee3982358f33e3329a35');
    expect(CjkCharsets.decodeGb18030(more), 'é㐀龦\u{10FFFF}');
    expect(CjkCharsets.encodeGb18030('é㐀龦\u{10FFFF}'), more);
    // labelled gbk / gb2312 pages go through the same decoder (GBK text is unchanged)
    expect(AppHttp.decodeWith(bytes, 'GBK'), text);
    expect(AppHttp.decodeWith(hex('d6d0cec4'), 'gb2312'), '中文');
    // no charset given and not UTF-8: GB18030
    expect(AppHttp.decodeBody(bytes), text);
  });

  test('URL encoding in GB18030 / Big5', () {
    expect(AppHttp.encodeWith('𠀀', 'gb18030'), hex('95328236'));
    expect(AppHttp.encodeWith('中文', 'GBK'), hex('d6d0cec4'));
    expect(AppHttp.encodeWith('中文', 'big5'), hex('a4a4a4e5'));
  });
}
