// Links to source / config files are imported instead of shown in the browser (e.g. 大灰狼's 轻悦时光 download button).
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/web/webview.dart';

void main() {
  test('json file links are import links, pages are not', () {
    expect(isImportFileUrl('https://v10.langge.uk/sy/download/%E8%BD%BB%E6%82%A6%E6%97%B6%E5%85%89app-%E5%A4%A7%E7%81%B0%E7%8B%BC%E8%9E%8D%E5%90%884.0(vip).json'), isTrue);
    expect(isImportFileUrl('http://example.test/sources/A.JSON'), isTrue);
    expect(isImportFileUrl('https://v10.langge.uk/user'), isFalse);
    expect(isImportFileUrl('http://svip.langge.uk/qydlogin.html'), isFalse);
    expect(isImportFileUrl('https://example.test/api?format=json'), isFalse);
    expect(isImportFileUrl('legado://import/bookSource?src=https%3A%2F%2Fs.test%2Fs.json'), isFalse); // handled as an import link
  });
}
