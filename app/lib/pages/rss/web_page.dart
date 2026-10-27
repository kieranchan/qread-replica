// pages/rss/web_page.dart — `WebPage` (size 0x48): a plain page for an url of an RSS source (login url of a source without login
// UI, `当前登录地址不正确!` is checked by the callers). The original's `_WebPageState` only hosts the web view; the replica reuses
// pages/web/webview.dart so cookies end up in the engine's store.
import 'package:flutter/material.dart';

import '../web/webview.dart';

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  final Map<String, String>? header;
  const WebPage({super.key, required this.url, this.title = '', this.header});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  @override
  Widget build(BuildContext context) => WebviewPage(url: widget.url, title: widget.title, header: widget.header);
}
