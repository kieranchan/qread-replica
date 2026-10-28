// widget/book/intro_html_flutter.dart — the original's intro renderer: flutter_html's `Html` (0x5acf50) with `onLinkTap`, font 14,
// line height 1.6, inside a SelectionArea. NOT imported by default: flutter_html 3.0.0 needs `html` 0.15.6 (0.15.7 removed the
// `matches` function it calls). With `dependency_overrides: html: 0.15.6` in pubspec.yaml, call [useFlutterHtmlIntro] at start-up.
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'intro_view.dart';

void useFlutterHtmlIntro() {
  IntroView.htmlBuilder = (context, html, onLinkTap, {onClickJs}) => SelectionArea(
        child: Html(
          key: const Key('intro_html'),
          data: html,
          style: {'body': Style(margin: Margins.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.6))},
          onLinkTap: (url, attrs, element) => onLinkTap(url),
          // `<button>名称 @onclick:js</button>` (0x5ad358): a button running the js, nothing without @onclick
          extensions: [
            TagExtension(
              tagsToExtend: {'button'},
              builder: (ctx) {
                final b = introButton(ctx.element?.text ?? '');
                if (b == null) return const SizedBox();
                final scheme = Theme.of(context).colorScheme;
                return TextButton(
                  style: TextButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
                  onPressed: () => onClickJs?.call(b.$2),
                  child: Text(b.$1),
                );
              },
            ),
          ],
        ),
      );
}
