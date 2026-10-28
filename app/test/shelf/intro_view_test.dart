// The detail page intro: <useweb> / @html: / <usehtml> / plain text (original 0x5ac588).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/book/intro_view.dart';

void main() {
  test('intro kinds', () {
    expect(introContent('<useweb><b>x</b></useweb>'), (IntroKind.web, '<b>x</b>'));
    expect(introContent(r'@html:<p class="$theme">a</p>', dark: true), (IntroKind.html, '<p class="dark">a</p>'));
    expect(introContent('<usehtml><b>粗</b></usehtml>'), (IntroKind.html, '<div><b>粗</b></div>'));
    expect(introContent('<p>一段</p>').$1, IntroKind.html);
    expect(introContent('第一行<br>第二行<br/>第三行'), (IntroKind.text, '第一行\n第二行\n第三行'));
  });

  testWidgets('html intros keep their structure, links are tappable; plain intros are selectable text', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [IntroView(intro: '<usehtml><p><b>粗体</b>简介</p><p>第二段<br>换行</p></usehtml>'), IntroView(intro: '纯文本<br>简介')])),
    ));
    await t.pump();
    final html = t.widget<SelectableText>(find.byKey(const Key('intro_html')));
    expect(html.textSpan!.toPlainText(), '粗体简介\n第二段\n换行');
    expect(find.text('纯文本\n简介'), findsOneWidget);
  });
}
