// widget/book/intro_html_flutter.dart — the original's intro renderer: flutter_html's `Html` (0x5acf50) with `onLinkTap`, font 14,
// line height 1.6, inside a SelectionArea. NOT imported by default: flutter_html 3.0.0 needs `html` 0.15.6 (0.15.7 removed the
// `matches` function it calls). With `dependency_overrides: html: 0.15.6` in pubspec.yaml, call [useFlutterHtmlIntro] at start-up.
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'intro_view.dart';

void useFlutterHtmlIntro() {
  IntroView.htmlBuilder = (context, html, onLinkTap) => SelectionArea(
        child: Html(
          key: const Key('intro_html'),
          data: html,
          style: {'body': Style(margin: Margins.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.6))},
          onLinkTap: (url, attrs, element) => onLinkTap(url),
        ),
      );
}
