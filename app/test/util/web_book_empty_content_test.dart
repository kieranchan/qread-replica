// `内容为空` of a Legado-style source carries the backend's own message when the answer was a small JSON object (2026-11-04: the
// 大灰狼 backend answered `{"code":-1,"msg":"获取内容失败: 内容为空"}` for a platform that was down and the reader only said 内容为空).
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/webbook/web_book.dart';

void main() {
  test('内容为空 carries the message of a small JSON answer', () {
    expect(WebBook.emptyContentMessage('{"code":-1,"msg":"获取内容失败: 内容为空","data":null}'), '内容为空（书源返回：获取内容失败: 内容为空）');
    expect(WebBook.emptyContentMessage(' {"code":0,"message":" 平台维护中 "} '), '内容为空（书源返回：平台维护中）');
    expect(WebBook.emptyContentMessage('{"code":0,"msg":"","data":null}'), '内容为空');
    expect(WebBook.emptyContentMessage('<html><body>msg</body></html>'), '内容为空');
    expect(WebBook.emptyContentMessage('{"msg":"broken'), '内容为空');
    expect(WebBook.emptyContentMessage(null), '内容为空');
    expect(WebBook.emptyContentMessage('{"msg":"x","pad":"${'a' * 3000}"}'), '内容为空', reason: 'a page-sized body is not parsed');
  });
}
