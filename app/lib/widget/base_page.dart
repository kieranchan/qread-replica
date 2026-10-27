// widget/base_page.dart — `BasePage<T>`: the State base class of most pages in the original, with the shared dialogs
// (confirm: 「取消」/「确定」 on a rounded AlertDialog; text input with 「请输入内容...」; a blocking progress dialog).
import 'package:flutter/material.dart';

/// Confirm dialog (title + message, 取消 / 确定). Resolves to true only on 确定.
Future<bool> showConfirmDialog(BuildContext context, {required String title, required String content, String ok = '确定', String cancel = '取消', Widget? extra}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: extra == null ? Text(content) : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(content), extra]),
      actions: [
        TextButton(key: const Key('dlg_cancel'), onPressed: () => Navigator.of(c).pop(false), child: Text(cancel)),
        ElevatedButton(key: const Key('dlg_ok'), onPressed: () => Navigator.of(c).pop(true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// Single-line (or multi-line) text input dialog; null when cancelled.
Future<String?> showInputDialog(BuildContext context,
    {required String title, String initial = '', String hint = '请输入内容...', int maxLines = 1, String ok = '确定'}) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: TextField(
        key: const Key('dlg_input'),
        controller: ctl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.of(c).pop(v) : null,
      ),
      actions: [
        TextButton(key: const Key('dlg_cancel'), onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
        ElevatedButton(key: const Key('dlg_ok'), onPressed: () => Navigator.of(c).pop(ctl.text), child: Text(ok)),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

/// One option of a single-choice dialog: a check mark on the current value; tapping pops the dialog with [value].
class ChoiceOption<V> extends StatelessWidget {
  final V value;
  final V current;
  final String title;

  const ChoiceOption({super.key, required this.value, required this.current, required this.title});

  @override
  Widget build(BuildContext context) {
    final on = value == current;
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
      trailing: on ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

abstract class BasePage<T extends StatefulWidget> extends State<T> {
  /// setState that ignores calls after dispose (async callbacks).
  void update([VoidCallback? fn]) {
    if (!mounted) return;
    setState(fn ?? () {});
  }

  Future<bool> confirm(String title, String content, {Widget? extra}) => showConfirmDialog(context, title: title, content: content, extra: extra);

  Future<String?> input(String title, {String initial = '', String hint = '请输入内容...', int maxLines = 1}) =>
      showInputDialog(context, title: title, initial: initial, hint: hint, maxLines: maxLines);

  /// Runs [task] behind a modal spinner with [message].
  Future<R> withLoading<R>(Future<R> Function() task, {String message = '加载中...'}) async {
    var open = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Flexible(child: Text(message))])),
      ),
    ).whenComplete(() => open = false);
    try {
      return await task();
    } finally {
      if (mounted && open) Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
