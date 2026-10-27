// Every route name a page opens through `Nav.openNamed` must be handled by one of the route tables wired in init/wiring.dart,
// otherwise the button only shows "… 尚未接入". Checked on the source text: names opened vs names the tables know.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Nav.openNamed target has a handler', () {
    final lib = Directory('lib');
    final opened = <String, String>{}; // name -> first file using it
    final call = RegExp(r"""(?:openNamed\(\s*[\w.]+\s*,|_named\()\s*'([a-z_0-9]+)'""");
    for (final f in lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in call.allMatches(f.readAsStringSync())) {
        opened.putIfAbsent(m.group(1)!, () => f.path);
      }
    }
    expect(opened, isNotEmpty);

    const tables = [
      'lib/pages/setting/extras_routes.dart',
      'lib/pages/read/reader_routes.dart',
      'lib/pages/book/shelf_routes.dart',
      'lib/pages/web/web_hooks.dart',
      'lib/init/glue_routes.dart',
    ];
    // map keys ('name': ...), switch cases (case 'name':), switch-expression arms ('a' || 'b' =>) and the glue name set
    final handledRe = RegExp(r"""'([a-z_0-9]+)'\s*(?::|=>|\|\||when)|case\s+'([a-z_0-9]+)'|names\s*=\s*\{([^}]*)\}""");
    final handled = <String>{};
    for (final t in tables) {
      for (final m in handledRe.allMatches(File(t).readAsStringSync())) {
        if (m.group(1) != null) handled.add(m.group(1)!);
        if (m.group(2) != null) handled.add(m.group(2)!);
        if (m.group(3) != null) handled.addAll(RegExp(r"'([a-z_0-9]+)'").allMatches(m.group(3)!).map((e) => e.group(1)!));
      }
    }
    final missing = {for (final e in opened.entries) if (!handled.contains(e.key)) e.key: e.value};
    expect(missing, isEmpty, reason: 'route names without a handler');
  });
}
