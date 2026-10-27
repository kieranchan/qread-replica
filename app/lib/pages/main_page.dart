// pages/main_page.dart — tab shell. Bookshelf / discovery are placeholders until Phase 2 ports them.
import 'package:flutter/material.dart';

import 'me_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 2;

  @override
  Widget build(BuildContext context) {
    const placeholders = [Center(child: Text('书架（待移植）')), Center(child: Text('发现（待移植）'))];
    return Scaffold(
      body: IndexedStack(index: _index, children: [...placeholders, const MePage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '书架'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: '发现'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}
