// widget/my_scaffold.dart — `MyScaffold`: the page scaffold with the app's flat app bar (centered title, no elevation, the
// theme's `Common.appbarcolor`-like surface colour).
import 'package:flutter/material.dart';

class MyScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? bottom;
  final Widget? titleWidget;

  const MyScaffold({
    super.key,
    this.title = '',
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.bottom,
    this.titleWidget,
  });

  @override
  State<MyScaffold> createState() => _MyScaffoldPageState();
}

class _MyScaffoldPageState extends State<MyScaffold> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.titleWidget ?? Text(widget.title),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.leading,
        actions: widget.actions,
        bottom: widget.bottom,
      ),
      body: widget.body,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }
}
