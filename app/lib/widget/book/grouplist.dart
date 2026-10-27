// widget/book/grouplist.dart — `Grouplist`: the 「分组管理」 dialog of the shelf (sub_6dfce4 / sub_6e0684 / sub_6e09cc).
// Add (「输入新分组名称」), rename (「编辑分组名称」 / 「输入新的分组名称」), delete (「是否删除分组《…》？删除后当前分组的书本会移动到全部！」
// / 「确认删除」), drag to reorder (ReorderableListView), show / hide a tab; name errors 「分组名称不能为空!」 / 「分组名称已存在!」.
// The built-in filter names (未分组 / 有声书 / 本地书 / 漫画 / 小说, see ShelfGroups) can be added like any group and then filter
// by their rule.
import 'package:flutter/material.dart';

import '../../data/bookself.dart';
import '../../util/toast.dart';
import '../base_page.dart';

class Grouplist extends StatefulWidget {
  const Grouplist({super.key});

  /// Opens the dialog.
  static Future<void> show(BuildContext context) => showDialog<void>(context: context, builder: (_) => const Grouplist());

  @override
  State<Grouplist> createState() => _GrouplistState();
}

class _GrouplistState extends BasePage<Grouplist> {
  final _ctl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Groupdata.load().then((_) => update(() => _loaded = true));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String? _check(String name, {String? except}) {
    final n = name.trim();
    if (n.isEmpty) return '分组名称不能为空!';
    if (n != except && (n == kAllGroup || Groupdata.contains(n))) return '分组名称已存在!';
    return null;
  }

  Future<void> _add() async {
    final err = _check(_ctl.text);
    if (err != null) {
      Toast.show(err, iserror: true);
      return;
    }
    await Groupdata.add(_ctl.text.trim());
    _ctl.clear();
    update();
  }

  Future<void> _rename(String g) async {
    final ctl = TextEditingController(text: g);
    final to = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑分组名称'),
        content: TextField(key: const Key('group_rename'), controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: '输入新的分组名称')),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.of(c).pop(ctl.text), child: const Text('确定')),
        ],
      ),
    );
    ctl.dispose();
    if (to == null || to.trim() == g) return;
    final err = _check(to, except: g);
    if (err != null) {
      Toast.show(err, iserror: true);
      return;
    }
    await Groupdata.rename(g, to.trim());
    update();
  }

  Future<void> _delete(String g) async {
    if (!await confirm('确认删除', '是否删除分组《$g》？删除后当前分组的书本会移动到全部！')) return;
    await Groupdata.remove(g);
    update();
  }

  @override
  Widget build(BuildContext context) {
    final groups = Groupdata.groups;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [Icon(Icons.folder_outlined), SizedBox(width: 8), Text('分组管理')]),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(key: const Key('group_new'), controller: _ctl, decoration: const InputDecoration(hintText: '输入新分组名称'), onSubmitted: (_) => _add())),
            IconButton(key: const Key('group_add'), icon: const Icon(Icons.add_circle_outline), onPressed: _add),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView.builder(
                    buildDefaultDragHandles: true,
                    itemCount: groups.length,
                    onReorderItem: (from, to) async {
                      await Groupdata.move(from, to);
                      update();
                    },
                    itemBuilder: (c, i) {
                      final g = groups[i];
                      final hidden = Groupdata.isHidden(g);
                      return ListTile(
                        key: ValueKey('grp_$g'),
                        contentPadding: const EdgeInsets.only(left: 4, right: 28),
                        title: Text(g, style: TextStyle(color: hidden ? Colors.grey : null)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () async {
                              await Groupdata.setHidden(g, !hidden);
                              update();
                            },
                          ),
                          IconButton(key: Key('grp_edit_$g'), icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _rename(g)),
                          IconButton(key: Key('grp_del_$g'), icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _delete(g)),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
    );
  }
}
