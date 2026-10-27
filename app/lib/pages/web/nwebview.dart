// pages/web/nwebview.dart — `NWebviewPage(url, title)`: an in-app web page (the 会员中心 page is opened with it).
// The original renders with WebF and answers JS->native calls (`paynew`); the replica's page is plain HTML that talks to
// the server itself, so a standard WebView is enough.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NWebviewPage extends StatefulWidget {
  final String url;
  final String title;
  const NWebviewPage({super.key, required this.url, required this.title});

  @override
  State<NWebviewPage> createState() => _NWebviewPageState();
}

class _NWebviewPageState extends State<NWebviewPage> {
  late final WebViewController _c;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onProgress: (p) => setState(() => _progress = p)))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Expanded(child: WebViewWidget(controller: _c)),
      ]),
    );
  }
}
