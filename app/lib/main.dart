import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'init/appinit.dart';
import 'pages/main_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInit.init();
  runApp(const QreadApp());
}

class QreadApp extends StatelessWidget {
  const QreadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '轻悦时光',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: const MainPage(),
    );
  }
}
