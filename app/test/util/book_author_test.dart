// Book.formatBookAuthor: the original's pattern 0x180980 strips a leading 作者： and a ` 著` after a space only.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/webbook/model/book.dart';

void main() {
  test('formatBookAuthor', () {
    expect(Book.formatBookAuthor('作者：三九音域'), '三九音域');
    expect(Book.formatBookAuthor(' 作 者 三九音域'), '三九音域');
    expect(Book.formatBookAuthor('三九音域 著'), '三九音域');
    expect(Book.formatBookAuthor('三九音域著'), '三九音域著');
    expect(Book.formatBookAuthor('三九音域'), '三九音域');
  });
}
