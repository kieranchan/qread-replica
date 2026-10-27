// Driver for `flutter drive`: writes every screenshot the integration test takes to app/screenshots/.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final f = File('screenshots/$name.png');
      await f.create(recursive: true);
      await f.writeAsBytes(bytes);
      return true;
    },
  );
}
