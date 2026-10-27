// util/epub/epub_rule_cache.dart — class 1420 `EpubRuleCache` (0x20 bytes) with one closure `String (Book)` (0x69d7c4): the cache key of the
// replace-rule results of an EPUB book. Here: the book's `bookUrl` hashed together with the rule fingerprint, so the cached chapter text
// ([BookRules]) is reused only while the rules stay the same.
import '../../models/book.dart';
import '../../read/api/read_file_store.dart';
import 'epub_page_counter.dart';

class EpubRuleCache {
  static String keyOf(Book book, RulePack rules) => ReadFileStore.md5Hex('${book.bookUrl}|${rules.signature}');
}
