import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'init/appinit.dart';
import 'init/wiring.dart';
import 'pages/main_page.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInit.init();
  await Wiring.init();
  runApp(const QreadApp());
}

class QreadApp extends StatelessWidget {
  const QreadApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = ThemeProvider.instance;
    return ListenableBuilder(
      listenable: tp,
      builder: (context, _) => GetMaterialApp(
        title: '轻悦时光',
        debugShowCheckedModeBanner: false,
        theme: tp.lightTheme,
        darkTheme: tp.darkTheme,
        themeMode: tp.themeMode,
        home: const MainPage(),
      ),
    );
  }
}
