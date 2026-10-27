// init/wiring.dart — lead-owned glue between the page areas: points the `Nav` hooks (common/nav.dart) and the start-up hooks of each
// area at the real implementations. Each area stays importable on its own; only this file (and main.dart) knows all of them.
import 'package:flutter/widgets.dart';

import '../common/nav.dart';
import '../pages/setting/extras_routes.dart';
import '../theme/extras_init.dart';
import '../util/legado/js_engines.dart';

abstract class Wiring {
  static bool _done = false;

  /// Area route tables tried in order by `Nav.openNamed`; each returns true when it handled the name.
  static final List<Future<bool> Function(BuildContext context, String name, {Object? arguments})> _routeTables = [
    ExtrasRoutes.open,
  ];

  /// Runs once after `AppInit.init()`.
  static Future<void> init() async {
    if (_done) return;
    _done = true;
    JsEngines.install();
    await ExtrasInit.init();

    final fallback = Nav.openNamed;
    Nav.openNamed = (context, name, {arguments}) async {
      for (final open in _routeTables) {
        if (!context.mounted) return;
        if (await open(context, name, arguments: arguments)) return;
      }
      if (context.mounted) await fallback(context, name, arguments: arguments);
    };
  }
}
