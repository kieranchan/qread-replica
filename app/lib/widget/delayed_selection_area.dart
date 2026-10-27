// widget/delayed_selection_area.dart — the text selection of the reader pages (original `DelayedSelectionArea` /
// `DelayedSelectionAreaState`, context menu 0x6e1b48: 复制 · 从这行开始朗读 · 全选本段 · 字典 · 搜索 · 替换净化 · 笔记/高亮, and the dictionary
// result sheet `DictionaryResultWidget` 0x104ba80..0x104d758 that queries Bing / 海词 / 新华词典 / 百度汉语).
//
// The selection itself is Flutter's [SelectionArea]; the page passes [onAction] and gets the selected plain text back. The dictionary
// lookup needs the network and the original's scraping endpoints; this build shows the selected word with links instead.
// TODO(asm 0x104bc44): online dictionary scraping (必应词典 / 海词 / 新华词典 / 百度汉语) is not ported.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

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

/// The dictionary sheet (original queries online dictionaries; see the TODO above).
class DictionaryResultWidget extends StatefulWidget {
  final String word;
  const DictionaryResultWidget({super.key, required this.word});

  @override
  State<DictionaryResultWidget> createState() => _DictionaryResultWidgetState();
}

class _DictionaryResultWidgetState extends State<DictionaryResultWidget> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('查询字典：${widget.word}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text('未找到解释'),
          ],
        ),
      ),
    );
  }
}
