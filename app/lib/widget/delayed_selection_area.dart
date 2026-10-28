// widget/delayed_selection_area.dart — the text selection of the reader pages (original `DelayedSelectionArea` /
// `DelayedSelectionAreaState`, context menu 0x6e1b48: 复制 · 从这行开始朗读 · 全选本段 · 字典 · 搜索 · 替换净化 · 笔记/高亮, and the dictionary
// result sheet `DictionaryResultWidget` 0x104ba80..0x104d758 that queries Bing / 海词 / 新华词典 / 百度汉语).
//
// The selection itself is Flutter's [SelectionArea]; the page passes [onAction] and gets the selected plain text back. 字典 opens
// [DictionaryResultWidget], which fetches the original's four pages (cn.bing.com/dict, apii.dict.cn/mini.php, hanyuguoxue.com/cidian,
// dict.baidu.com) and shows the extracted parts as HTML (flutter_html), like the original.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../util/toast.dart';

/// The menu actions of the original, in order.
enum SelectionAction {
  copy('复制'),
  readFromHere('从这行开始朗读'),
  selectParagraph('全选本段'),
  dictionary('字典'),
  search('搜索'),
  replace('替换净化'),
  note('笔记/高亮');

  final String label;
  const SelectionAction(this.label);
}

/// What the page receives for a menu action.
class NoteActionPayload {
  final SelectionAction action;
  final String text;
  const NoteActionPayload(this.action, this.text);
}

class DelayedSelectionArea extends StatefulWidget {
  final Widget child;

  /// Called for every menu action except [SelectionAction.copy], which copies by itself (and is also reported).
  final void Function(NoteActionPayload payload)? onAction;

  /// Selection on/off (the page disables it while the menus are open or a page turn is running).
  final bool enabled;

  const DelayedSelectionArea({super.key, required this.child, this.onAction, this.enabled = true});

  @override
  State<DelayedSelectionArea> createState() => DelayedSelectionAreaState();
}

class DelayedSelectionAreaState extends State<DelayedSelectionArea> {
  SelectedContent? _selected;

  String get selectedText => _selected?.plainText ?? '';

  void _run(SelectableRegionState region, SelectionAction action) {
    final text = selectedText;
    region.hideToolbar();
    if (action == SelectionAction.copy) {
      Clipboard.setData(ClipboardData(text: text));
    } else if (action == SelectionAction.dictionary) {
      showDictionary(context, text);
    }
    if (action != SelectionAction.selectParagraph) region.clearSelection();
    widget.onAction?.call(NoteActionPayload(action, text));
  }

  static Future<void> showDictionary(BuildContext context, String word) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => DictionaryResultWidget(word: word),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return SelectionArea(
      onSelectionChanged: (c) => _selected = c,
      contextMenuBuilder: (ctx, region) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: region.contextMenuAnchors,
        buttonItems: [
          for (final a in SelectionAction.values) ContextMenuButtonItem(label: a.label, onPressed: () => _run(region, a)),
        ],
      ),
      child: widget.child,
    );
  }
}

/// The same menu for the paged reader, which selects by long press itself (a [SelectionArea] would take the taps and horizontal drags
/// the page turning needs). Shown near the selection.
class ReaderSelectionMenu extends StatelessWidget {
  final void Function(SelectionAction action) onAction;
  const ReaderSelectionMenu({super.key, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE303030),
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in SelectionAction.values)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                onPressed: () => onAction(a),
                child: Text(a.label, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The online dictionaries of the original (static closures 0x6e278c / 0x6e27bc / 0x6e27ec / 0x6e281c): each turns a word into an
/// HTML fragment shown by the sheet, or one of the original's messages ("未找到解释", "获取…失败：…").
class OnlineDictionary {
  final String name;
  final String Function(String word) url;
  final String Function(String html) parse;
  const OnlineDictionary(this.name, this.url, this.parse);

  /// GET of a page (tests point it at a local server).
  static Future<String> Function(String url) fetch = _get;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    },
  ));

  static Future<String> _get(String url) async => (await _dio.get<String>(url)).data ?? '';

  Future<String> lookup(String word) async {
    final u = url(word);
    debugPrint('$name URL: $u');
    String page;
    try {
      page = await fetch(u);
    } catch (e) {
      return '获取$name失败：$e';
    }
    try {
      return parse(page);
    } catch (e) {
      return '解析$name错误：$e';
    }
  }

  static String _enc(String w) => Uri.encodeQueryComponent(w.trim());

  /// 必应词典 (0x104bc44): headword in red, pronunciation in orange, part of speech in green brackets, definitions, then the bilingual
  /// examples; the noise blocks of the page are removed first.
  static final OnlineDictionary bing = OnlineDictionary('必应词典', (w) => 'https://cn.bing.com/dict/search?q=${_enc(w)}&qs=ds&form=CM', (page) {
    final doc = html_parser.parse(page);
    for (final sel in ['#id_clsp_web_More', '#id_clsp_web_Less', '.b_pag.b_cards', '.gl_none', '#ex_id', '.sen_count', '.wsepr', '.li_exs']) {
      for (final e in doc.querySelectorAll(sel)) {
        e.remove();
      }
    }
    final head = doc.querySelector('#headword')?.text.trim() ?? '';
    final defs = doc.querySelectorAll('.qdef ul li');
    if (head.isEmpty && defs.isEmpty) return '未找到解释';
    final b = StringBuffer();
    if (head.isNotEmpty) b.write('<br><h1><span style="color:red">${_esc(head)}</span></h1>');
    final pron = doc.querySelector('.hd_tf_lh')?.text.trim() ?? '';
    if (pron.isNotEmpty) b.write('<p style="color:#e65100">${_esc(pron.replaceAll(RegExp(r'\s+'), ' '))}</p>');
    for (final li in defs) {
      final pos = li.querySelector('.pos')?.text.trim() ?? '';
      final def = li.querySelector('.def')?.text.trim() ?? li.text.trim();
      b.write('<p>');
      if (pos.isNotEmpty) b.write('<span style="color:#7DC475">【${_esc(pos)}】</span>');
      b.write('${_esc(def)}</p>');
    }
    final sentences = doc.querySelectorAll('#sentenceSeg .se_li');
    if (sentences.isNotEmpty) {
      b.write('<br><h4><span style="color:#4685A4">例句</span></h4>');
      for (final s in sentences.take(6)) {
        final en = s.querySelector('.sen_en')?.text.trim() ?? '';
        final cn = s.querySelector('.sen_cn')?.text.trim() ?? '';
        if (en.isEmpty && cn.isEmpty) continue;
        b.write('<p>${_esc(en)}<br><span style="color:#e65100">${_esc(cn)}</span></p>');
      }
    }
    return b.toString();
  });

  /// 海词 (0x104d47c): the mini page is already a short HTML fragment.
  static final OnlineDictionary dictcn = OnlineDictionary('海词英文', (w) => 'https://apii.dict.cn/mini.php?q=${_enc(w)}', (page) {
    final body = html_parser.parse(page).body;
    final text = body?.text.trim() ?? '';
    return text.isEmpty ? '未找到解释' : body!.innerHtml;
  });

  /// 新华词典 (0x104d5a4, hanyuguoxue): the `.card` blocks.
  static final OnlineDictionary xinhua = OnlineDictionary('新华词典', (w) => 'https://www.hanyuguoxue.com/cidian/search?words=${_enc(w)}', (page) {
    final cards = html_parser.parse(page).querySelectorAll('.card');
    if (cards.isEmpty) return '未找到解释';
    return cards.map((c) => c.outerHtml).join('<br>');
  });

  /// 百度汉语 (0x104d758): the text of `content-panel`, whitespace collapsed.
  static final OnlineDictionary baidu = OnlineDictionary('百度汉语', (w) => 'https://dict.baidu.com/s?wd=${_enc(w)}', (page) {
    final doc = html_parser.parse(page);
    final panel = doc.querySelector('#content-panel') ?? doc.querySelector('.content-panel');
    final text = panel?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return text.isEmpty ? '未找到解释' : '<p>${_esc(text)}</p>';
  });

  static const List<String> tabs = ['必应词典', '海词', '新华词典', '百度汉语'];
  static List<OnlineDictionary> get all => [bing, dictcn, xinhua, baidu];

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

/// The dictionary sheet (`_DictionaryResultWidgetState`): one tab per dictionary, the result rendered as HTML, links open outside.
class DictionaryResultWidget extends StatefulWidget {
  final String word;
  const DictionaryResultWidget({super.key, required this.word});

  @override
  State<DictionaryResultWidget> createState() => _DictionaryResultWidgetState();
}

class _DictionaryResultWidgetState extends State<DictionaryResultWidget> {
  int _tab = 0;
  final Map<int, Future<String>> _results = {};

  Future<String> _result(int i) => _results.putIfAbsent(i, () => OnlineDictionary.all[i].lookup(widget.word));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('查询字典：${widget.word}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < OnlineDictionary.tabs.length; i++)
                  ChoiceChip(label: Text(OnlineDictionary.tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<String>(
                  key: ValueKey(_tab),
                  future: _result(_tab),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    return SingleChildScrollView(
                      child: Html(
                        data: snap.data!,
                        onLinkTap: (url, attributes, element) async {
                          final u = Uri.tryParse(url ?? '');
                          if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) Toast.show('无法打开链接: $url');
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
