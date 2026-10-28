// Own file: the drag writes the shelf from the UI (see support.dart, pumpPage).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/pages/bookshelf_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/widget/book/shelf_prefs.dart';

import 'support.dart';

void main() {
  testWidgets('drag a book onto another: 手动排序 (booklistordrer 3), the dragged book takes the target place', (t) async {
    final books = fixtureBooks().take(3).toList();
    final env = await pumpPage(t, const BookshelfPage(), books: books);
    addTearDown(env.dispose);
    final urls = BookSelfN.books.map((b) => b.bookUrl).toList();
    final first = urls.first, last = urls.last;
    // shown order (最近阅读 by default) becomes the stored order, then the first shown book moves to the last one's place
    final shown = t.widgetList<DragTarget<Object>>(find.byWidgetPredicate((w) => w is DragTarget)).map((w) => (w.key as ValueKey<String>).value.substring(5)).toList();
    final gesture = await t.startGesture(t.getCenter(find.byKey(Key('book_${shown.first}'))));
    await t.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await t.pump();
    await gesture.moveTo(t.getCenter(find.byKey(Key('book_${shown.last}'))));
    await t.pump();
    await gesture.up();
    await settle(t);
    expect(Storage.getString(ShelfPrefs.sortKey), '3');
    final after = BookSelfN.books.map((b) => b.bookUrl).toList();
    expect(after, [...shown.skip(1), shown.first]);
    expect(after.toSet(), {first, last, ...urls});
  });
}
