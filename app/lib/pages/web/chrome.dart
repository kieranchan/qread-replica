// pages/web/chrome.dart — `ChromePage`, the in-app browser entry (the 浏览器 item of 「我的」), and `UAType`, the user-agent choice
// stored in prefs `userAgentType` (int index). The original's `_ChromePageState` here only hosts the InAppWebView browser of
// chrome_inapp.dart.
import 'package:flutter/material.dart';

import '../../storage/storage.dart';
import 'chrome_inapp.dart';

/// The six user agents of the browser (maps built by 0x9765d0: `UAType → String` labels and agents, in enum order).
enum UAType {
  defaultUA('默认UA', null),
  pc('PC UA', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36'),
  mac('Mac UA', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36'),
  android('安卓UA', 'Mozilla/5.0 (Linux; Android 13; SM-G998U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36'),
  ios('iOS UA', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/123.0.6312.58 Mobile/15E148 Safari/604.1'),
  // 0x9765d0 reads static 0x1e1c (analysis/inventory/statics.tsv)
  harmony('鸿蒙UA', 'Mozilla/5.0 (Phone; OpenHarmony 6.0; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.120 Mobile HuaweiBrowser/5.1.11.312');

  final String label;
  final String? ua;
  const UAType(this.label, this.ua);

  /// 0x5d8440: `toInt(userAgentType)` into the six values.
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
