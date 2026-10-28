// widget/book/intro_view.dart — the 简介 of the detail page (original 0x5ac588):
//   * `<useweb>…</useweb>`: the html in an embedded web view;
//   * `@html:…`: html, with `$theme` replaced by `dark` / `day`;
//   * `<usehtml>…</usehtml>` (turned into a `<div>`), or text with `<p>` / closing tags: html, rendered by flutter_html in the original
//     (`Html` with `onLinkTap` → in-app browser);
//   * anything else: plain selectable text, `<br>` / `<br/>` / `</br>` become line breaks.
//
// Html rendering goes through [IntroView.htmlBuilder]. flutter_html 3.0.0 does not compile against `html` 0.15.7 (it calls the
// `matches` function that 0.15.7 removed), so the default is a small renderer on package:html (paragraphs, line breaks, bold /
// italic, links, headings); `intro_html_flutter.dart` switches to flutter_html once `html` is pinned to 0.15.6.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../pages/web/web_engine.dart';
import '../../pages/web/webview.dart';

enum IntroKind { web, html, text }

/// How [intro] is shown and the content to show (html for [IntroKind.web] / [IntroKind.html], text otherwise).
(IntroKind, String) introContent(String intro, {bool dark = false}) {
  var t = intro.trim();
  if (t.contains('<useweb>')) return (IntroKind.web, t.replaceAll('<useweb>', '').replaceAll('</useweb>', ''));
  if (t.startsWith('@html:')) return (IntroKind.html, t.substring(6).replaceAll(r'$theme', dark ? 'dark' : 'day'));
  if (t.contains('<usehtml>')) return (IntroKind.html, t.replaceAll('<usehtml>', '<div>').replaceAll('</usehtml>', '</div>'));
  if (t.contains('<p>') || t.contains('</')) return (IntroKind.html, t);
  t = t.replaceAll('<br>', '\n').replaceAll('<br/>', '\n').replaceAll('</br>', '\n');
  return (IntroKind.text, t);
}

typedef IntroHtmlBuilder = Widget Function(BuildContext context, String html, void Function(String? url) onLinkTap,
    {void Function(String js)? onClickJs});

/// `<button>名称 @onclick:js</button>` of an html intro (0x5ad358): the label and the js, null without `@onclick`.
(String, String)? introButton(String text) {
  if (!text.contains('@onclick')) return null;
  final parts = text.split('@onclick:');
  return (parts.first.trim(), parts.length > 1 ? parts.sublist(1).join('@onclick:').trim() : '');
}

class IntroView extends StatefulWidget {
  final String intro;

  /// Runs the js of an `@onclick:` button (the detail page hands it to the book's source page).
  final void Function(String js)? onClickJs;

  const IntroView({super.key, required this.intro, this.onClickJs});

  /// Renders html intros; see the file comment.
  static IntroHtmlBuilder htmlBuilder = simpleHtml;

  /// The built-in renderer: the text of the html with its structure (blocks, `<br>`, headings, bold / italic, links); a `<button>`
  /// with `@onclick:` becomes a button running its js (one without is left out, as in the original).
  static Widget simpleHtml(BuildContext context, String html, void Function(String? url) onLinkTap, {void Function(String js)? onClickJs}) {
    final base = DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 14, height: 1.6));
    final scheme = Theme.of(context).colorScheme;
    final link = TextStyle(color: scheme.primary, decoration: TextDecoration.underline);
    final spans = <InlineSpan>[];
    var buttons = false;
    void block() {
      if (spans.isNotEmpty && !(spans.last is TextSpan && ((spans.last as TextSpan).text ?? '').endsWith('\n'))) spans.add(const TextSpan(text: '\n'));
    }

    void walk(dom.Node n, TextStyle style) {
      if (n is dom.Text) {
        final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
        if (t.trim().isNotEmpty || (spans.isNotEmpty && t == ' ')) spans.add(TextSpan(text: t, style: style));
        return;
      }
      if (n is! dom.Element) {
        for (final c in n.nodes) {
          walk(c, style);
        }
        return;
      }
      final tag = n.localName ?? '';
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'button') {
        final b = introButton(n.text);
        if (b == null) return;
        buttons = true;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: TextButton(
            style: TextButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
            onPressed: () => onClickJs?.call(b.$2),
            child: Text(b.$1),
          ),
        ));
        return;
      }
      if (tag == 'br') {
        spans.add(const TextSpan(text: '\n'));
        return;
      }
      var s = style;
      if (tag == 'b' || tag == 'strong') s = s.copyWith(fontWeight: FontWeight.bold);
      if (tag == 'i' || tag == 'em') s = s.copyWith(fontStyle: FontStyle.italic);
      if (RegExp(r'^h[1-6]$').hasMatch(tag)) s = s.copyWith(fontWeight: FontWeight.bold, fontSize: 16);
      final isBlock = const {'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', 'blockquote', 'tr'}.contains(tag);
      if (isBlock) block();
      if (tag == 'a' && (n.attributes['href'] ?? '').isNotEmpty) {
        final href = n.attributes['href'];
        spans.add(TextSpan(text: n.text, style: s.merge(link), recognizer: TapGestureRecognizer()..onTap = () => onLinkTap(href)));
      } else {
        for (final c in n.nodes) {
          walk(c, s);
        }
      }
      if (isBlock) block();
    }

    walk(html_parser.parseFragment(html), base);
    while (spans.isNotEmpty && spans.last is TextSpan && (spans.last as TextSpan).text == '\n') {
      spans.removeLast();
    }
    // SelectableText cannot hold widgets: with buttons the text is selectable through a SelectionArea
    if (buttons) return SelectionArea(child: Text.rich(TextSpan(children: spans), key: const Key('intro_html')));
    return SelectableText.rich(TextSpan(children: spans), key: const Key('intro_html'));
  }

  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> {
  QWebController? _web;
  String? _loaded;

  @override
  void dispose() {
    _web?.dispose();
    super.dispose();
  }

  void _openLink(String? url) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebviewPage(url: url)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (kind, content) = introContent(widget.intro, dark: dark);
    switch (kind) {
      case IntroKind.web:
        final web = _web ??= WebEngine.create();
        if (_loaded != content) {
          _loaded = content;
          web.loadHtml(content);
        }
        return SizedBox(key: const Key('intro_web'), height: 320, child: web.build(context));
      case IntroKind.html:
        return IntroView.htmlBuilder(context, content, _openLink, onClickJs: widget.onClickJs);
      case IntroKind.text:
        return SelectableText(content, key: const Key('intro_text'), style: const TextStyle(fontSize: 14, height: 1.6));
    }
  }
}
