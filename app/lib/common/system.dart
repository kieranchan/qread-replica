// common/system.dart — `System.pagenames` (static late final Map<String, String>, 0x4120): page id -> display name. The theme editor
// (`pages/theme/new_theme_page.dart`, 绑定页面 / 未绑定页面) lists the pages a style can be bound to from this map; page code registers
// its entries (`System.pagenames['bookshelf'] = '书架'`). TODO(asm 0x1036e20): the original's map literal is built in a static
// initializer that is not recoverable; the replica starts empty and lets the pages register themselves.
abstract class System {
  static final Map<String, String> pagenames = <String, String>{};
}
