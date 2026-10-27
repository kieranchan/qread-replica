// pages/web/chrome.dart — `ChromePage`, the in-app browser entry (the 浏览器 item of 「我的」), and `UAType`, the user-agent choice
// stored in prefs `userAgentType` (int index). The original's `_ChromePageState` here only hosts the InAppWebView browser of
// chrome_inapp.dart.
import 'package:flutter/material.dart';

import '../../storage/storage.dart';
import 'chrome_inapp.dart';

enum UAType {
  defaultUA('默认', null),
  android('安卓', 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36'),
  iphone('iPhone', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1'),
  ipad('iPad', 'Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1'),
  windows('电脑(Windows)', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'),
  mac('电脑(Mac)', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15');

  final String label;
  final String? ua;
  const UAType(this.label, this.ua);

  // TODO(asm 0x5d8440): the original's six UAType values and their strings are const objects not visible in the digest;
  // labels and user agents above are the replica's.
  static UAType get current {
    final i = Storage.getInt('userAgentType', 0);
    return i >= 0 && i < values.length ? values[i] : UAType.defaultUA;
  }

  static Future<void> save(UAType t) => Storage.setInt('userAgentType', t.index);
}

class ChromePage extends StatefulWidget {
  /// Optional page to open first (otherwise the bookmark start page).
  final String? url;
  const ChromePage({super.key, this.url});

  @override
  State<ChromePage> createState() => _ChromePageState();
}

class _ChromePageState extends State<ChromePage> {
  @override
  Widget build(BuildContext context) => ChromeInappPage(url: widget.url);
}
