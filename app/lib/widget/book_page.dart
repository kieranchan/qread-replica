// widget/book_page.dart — `BookApiPage<T>`: the State base of the shelf, detail, discovery and list pages in the original, with
// the book operations they share:
//   choose group      0x536694 (「选择分组」, 取消 / 确定)
//   add to shelf      0x566de8 (「加入书架」 「确定要将《…》加入书架吗？」 with 「选择分组」) and 0x5661f8 (「选择要加入的书架分组」)
//   book variable     0x5396a4 / 0x53a074 (「设置书籍变量」, 「请输入内容...」, 「清空」, 「确定」)
//   clear cache       in 0xf736c4 (「操作确认」 「是否要清理当前书本缓存？」 → 「清除缓存成功」 / 「清除缓存失败:」)
//   change source     0x53a1b4 (「换源成功」)
// plus the helpers every list needs (local-book test, type label, the shelf's built-in filter groups).
import 'package:flutter/material.dart';

import '../data/bookself.dart';
import '../models/book.dart';
import '../read/api/book_content.dart';
import '../read/api/readapi.dart';
import '../read/local_book_importer.dart';
import '../storage/storage.dart';
import '../util/toast.dart';
import 'base_page.dart';

/// Local books: the shelf code of the original tests `origin == "phone_book"` (0xf6b8bc, 0xfa8024); the reading core marks
/// imported files `loc_book` (0xd97fa4). Both mean "a file on this device".
bool isLocalShelfBook(Book b) => b.origin == kPhoneBook || b.origin == ReadApi.localOrigin;

/// Book `type` → label (sub_5a12e8): 1 听书, 2 漫画, 4 短剧, anything else 小说.
String bookTypeLabel(int type) => switch (type) { 1 => '听书', 2 => '漫画', 4 => '短剧', _ => '小说' };

/// The built-in filter groups of the shelf (0xe65d78 / 0x1c1ecc): they are not stored in `bookgroup` but select books by a rule.
abstract class ShelfGroups {
  static const String ungrouped = '未分组';
  static const String audio = '有声书';
  static const String local = '本地书';
  static const String comic = '漫画';
  static const String novel = '小说';
  static const List<String> builtin = [ungrouped, audio, local, comic, novel];

  /// 0xe65d78: the filter of a group tab. `''`/「全部」 = everything; 未分组 = no group; 有声书 = type 1; 本地书 = local file;
  /// 漫画 = type 2; 小说 = type 0; any other name = the user group.
  static bool matches(Book b, String group) {
    switch (group) {
      case '':
      case kAllGroup:
        return true;
      case ungrouped:
        return b.bookgroup.trim().isEmpty || b.bookgroup == kAllGroup;
      case audio:
        return b.type_ == 1;
      case local:
        return isLocalShelfBook(b);
      case comic:
        return b.type_ == 2;
      case novel:
        return b.type_ == 0;
      default:
        return BookSelfN.inGroup(b, group);
    }
  }
}

/// Per-book variable of the source engine (「书本变量」). TODO(asm 0x53a074): the original hands the text to the engine
/// (`setbookVariable`); the replica keeps it in prefs under `bookVariable<bookUrl>` until the engine area exposes it.
abstract class BookVariables {
  static String key(String bookUrl) => 'bookVariable$bookUrl';
  static String get(String bookUrl) => Storage.getString(key(bookUrl));
  static Future<void> set(String bookUrl, String value) =>
      value.isEmpty ? Storage.remove(key(bookUrl)) : Storage.setString(key(bookUrl), value);
}

/// Replaces [old] on the shelf by [found] (change source): the new copy keeps position, group, progress and flags of the old
/// one. Returns the stored book.
Future<Book> replaceShelfBook(Book old, Book found) async {
  await BookSelfN.load();
  final pos = BookSelfN.books.indexWhere((b) => b.bookUrl == old.bookUrl);
  final copy = Book.fromJson(found.toJson())
    ..bookgroup = old.bookgroup
    ..durChapterIndex = old.durChapterIndex
    ..durChapterPos = old.durChapterPos
    ..durChapterTitle = old.durChapterTitle
    ..durChapterTime = old.durChapterTime
    ..readchapter = old.readchapter
    ..update = old.update
    ..useReplaceRule = old.useReplaceRule
    ..useai = old.useai
    ..reverseCatalog = old.reverseCatalog;
  if (copy.type_ == 0) copy.type_ = old.type_;
  if (pos < 0) return BookSelfN.add(copy);
  if (copy.bookUrl != old.bookUrl) await BookSelfN.remove(old.bookUrl);
  final stored = await BookSelfN.add(copy);
  await BookSelfN.updateProgress(stored.bookUrl, index: old.durChapterIndex, pos: old.durChapterPos, title: old.durChapterTitle, readchapter: old.readchapter);
  await BookSelfN.setGroup(stored.bookUrl, old.bookgroup);
  final now = BookSelfN.books.indexWhere((b) => b.bookUrl == stored.bookUrl);
  if (now >= 0 && now != pos) await BookSelfN.move(now, pos);
  return BookSelfN.get(stored.bookUrl) ?? stored;
}

/// Removes books from the shelf; with [withCache] their downloaded chapters (and, for local books, the imported file) go too.
Future<int> deleteShelfBooks(Iterable<Book> books, {bool withCache = false, BookContent content = const BookContent()}) async {
  final list = books.toList();
  final n = await BookSelfN.removeMany(list.map((b) => b.bookUrl));
  if (withCache) {
    for (final b in list) {
      try {
        if (isLocalShelfBook(b)) {
          await const LocalBookImporter().delete(b);
        } else {
          await content.deleteBook(b.bookUrl);
        }
      } catch (e) {
        debugPrint('删除缓存失败 $e');
      }
    }
  }
  return n;
}

abstract class BookApiPage<T extends StatefulWidget> extends BasePage<T> {
  /// 0x536694: 「选择分组」. Resolves to the chosen group (`''` = no group), null when cancelled.
  Future<String?> chooseGroup({String current = ''}) async {
    await Groupdata.load();
    if (!mounted) return null;
    final groups = ['', ...Groupdata.groups];
    var sel = current;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Icon(Icons.folder_outlined, color: Color(0xFF7CB7B2)), SizedBox(width: 8), Text('选择分组')]),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (c, i) {
                final g = groups[i];
                final on = g == sel;
                return ListTile(
                  key: Key('group_opt_${g.isEmpty ? kAllGroup : g}'),
                  title: Text(g.isEmpty ? kAllGroup : g, style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
                  trailing: on ? const Icon(Icons.check_circle, color: Color(0xFF7CB7B2)) : null,
                  onTap: () => set(() => sel = g),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
            ElevatedButton(key: const Key('group_ok'), onPressed: () => Navigator.of(c).pop(sel), child: const Text('确定')),
          ],
        );
      }),
    );
  }

  /// Moves books into a group chosen in [chooseGroup] (「移动分组」 / 「移入分组」).
  Future<bool> moveToGroup(List<Book> books) async {
    if (books.isEmpty) return false;
    final g = await chooseGroup(current: books.length == 1 ? books.first.bookgroup : '');
    if (g == null) return false;
    try {
      await BookSelfN.setGroupMany(books.map((b) => b.bookUrl), g);
      Toast.show('修改成功');
      return true;
    } catch (e) {
      Toast.show('修改失败: $e', iserror: true);
      return false;
    }
  }

  /// 0x566de8: 「加入书架」 — confirm with a group picker, then store the book. Returns the stored copy (null when cancelled).
  Future<Book?> addToShelf(Book book) async {
    var group = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('加入书架'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('确定要将《${book.name}》加入书架吗？'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add_choose_group'),
              icon: const Icon(Icons.folder_outlined),
              label: Text(group.isEmpty ? '选择分组' : group),
              onPressed: () async {
                final g = await chooseGroup(current: group);
                if (g != null) set(() => group = g);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            ElevatedButton(key: const Key('add_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final stored = await BookSelfN.add(Book.fromJson(book.toJson())..bookgroup = group);
    if (group.isNotEmpty) await BookSelfN.setGroup(stored.bookUrl, group);
    Toast.show('操作成功');
    return stored;
  }

  /// 「删除书籍」 / batch delete: 「删除确认」 「确定要删除这些书本吗？」 (0xf6f844) with the cache option.
  Future<bool> deleteBooks(List<Book> books) async {
    if (books.isEmpty) return false;
    var withCache = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('删除确认'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(books.length == 1 ? '确定要删除《${books.first.name}》吗？' : '确定要删除这些书本吗？'),
            // TODO(asm 0xf6f844): the original deletes the shelf entries only; the cache option is the replica's (brief).
            CheckboxListTile(
              key: const Key('del_with_cache'),
              contentPadding: EdgeInsets.zero,
              value: withCache,
              onChanged: (v) => set(() => withCache = v ?? false),
              title: const Text('同时删除缓存'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            ElevatedButton(key: const Key('del_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('删除')),
          ],
        ),
      ),
    );
    if (ok != true) return false;
    try {
      await deleteShelfBooks(books, withCache: withCache);
      return true;
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
      return false;
    }
  }

  /// 「清除缓存」 of one book.
  Future<void> clearBookCache(Book book) async {
    if (!await confirm('操作确认', '是否要清理当前书本缓存？')) return;
    try {
      await const BookContent().deleteBook(book.bookUrl);
      Toast.show('清除缓存成功');
    } catch (e) {
      Toast.show('清除缓存失败:$e', iserror: true);
    }
  }

  /// 0x5396a4: 「设置书籍变量」.
  Future<void> editBookVariable(Book book) async {
    final ctl = TextEditingController(text: BookVariables.get(book.bookUrl));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('设置书籍变量', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(c).pop(false)),
        ]),
        content: SizedBox(
          width: 400,
          child: TextField(key: const Key('book_var'), controller: ctl, maxLines: 8, minLines: 4, decoration: const InputDecoration(hintText: '请输入内容...')),
        ),
        actions: [
          TextButton.icon(icon: const Icon(Icons.delete_outline), label: const Text('清空'), onPressed: () => ctl.clear()),
          ElevatedButton(key: const Key('book_var_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      await BookVariables.set(book.bookUrl, ctl.text);
      Toast.show('操作成功');
    }
    ctl.dispose();
  }
}
