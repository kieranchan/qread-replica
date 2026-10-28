// pages/read/pages/novel/views/top_menu.dart — the reader's top bar (original `TopMenu` 0x10e4d88 + entry map 0x958114, `TopMenuEntry`,
// `_BookmarkButton`). Layout: back button, book / chapter title, the buttons the user picked (`topMenuButtons`, default
// browser / changeSource / refresh; editing the list is a member feature in read_more_setting) and a "更多" menu with every entry.
// Entry ids and labels are the original's: batchDownload 批量下载, sourceLogin 书源登录, chapterUrl 正文地址, bookmark 书签,
// searchContent 搜索正文, aiPurify Ai净化, replacePurify 替换净化, effectivePurify 起效净化, highlightRule 高亮规则, buyChapter 购买章节,
// backupSetting 备份设置, restoreSetting 恢复设置, browser 用浏览器打开, changeSource 换源, refresh 刷新, showLog 显示日志.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../api/userapi.dart';
import '../../../../../common/nav.dart';
import '../../../../../data/bookself.dart';
import '../../../../../data/replace.dart';
import '../../../../../models/book.dart';
import '../../../../../models/bookchapter.dart';
import '../../../../../read/api/readapi.dart';
import '../../../../../read/util/cache_book.dart';
import '../../../../../read/util/down_notification.dart';
import '../../../../../read/util/replace_rules.dart';
import '../../../../../storage/setting.dart';
import '../../../../../storage/storage.dart';
import '../../../../../util/source/source_events.dart';
import '../../../../../util/toast.dart';
import '../../../../../widget/ui/q_glass.dart';
import '../../../../highlight/highlight_rule_setting.dart';
import '../../../../replace/replace_rule_setting.dart';
import '../../../web_book_loader.dart';
import 'reader_host.dart';

class TopMenuEntry {
  final String id;
  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context, ReaderHost host) run;
  const TopMenuEntry(this.id, this.icon, this.label, this.run);
}

/// The prefs keys of the reading settings (`StorageItem.readitems`, initializer 0x958e9c; the static key names are read from the snapshot's
/// field table): 备份设置 uploads `{key: value}` of these as cloud item `readitems`, 恢复设置 writes them back.
const List<String> readerBackupKeys = [
  'ttsrate', 'ttsEngine', 'needdp', 'chinesetype', 'turntime', 'cantrun', 'cantnext', 'waitread', 'fontSizedefault', 'fontSizeopen',
  'fontSizevalue', 'background', 'darkbackground', 'wakelock', 'wakelockTimeout', 'volumeButton', 'kong', 'fontFamily', 'useFixedFont',
  'bottomfix', 'showTop', 'showFullpos', 'showPageNumber', 'fullNext', 'paragraphSpacing', 'lineHeight', 'ispad', 'isbold',
  'bottomMargin', 'topMargin', 'horizontalMargin', 'turnType0', 'turnType2', 'hidetop', 'simplified1', 'turn', 'skipStartTime',
  'skipEndTime', 'readspeed', 'needupdate', 'continueRead', 'dpstyle', 'listemcachenum', 'needopacity', 'letterSpacing', 'safeTop',
  'safeBottom', 'leftMargin', 'rightMargin', 'titleTopMargin', 'titleBottomMargin', 'showProgress', 'pageTurnSpeed', 'fan',
  'menuSliderType', 'headerFooterFontSize', 'headerLeftMargin', 'headerRightMargin', 'footerLeftMargin', 'footerRightMargin',
  'customFooterLeft', 'customFooterCenter', 'customFooterRight', 'customHeaderLeft', 'customHeaderCenter', 'customHeaderRight',
  'titleAlign', 'fontWeight12345', 'titlefontSize', 'hidebottom', 'menuSliderType2', 'readHighlightType', 'underline', 'underlineStyle',
  'underlineFullWidth', 'fen', 'two', 'needcss2', 'topMenuButtons', 'aichat',
];

abstract class TopMenuActions {
  /// Cloud item of the reading settings.
  static const String cloudItem = 'readitems';

  /// The account server's item store (`UserApi.setItemJsonFile` / `getItemJson`; tests replace them).
  static Future<void> Function(String item, String content) uploadItem = UserApi.setItemJsonFile;
  static Future<String> Function(String item) downloadItem = UserApi.getItemJson;

  static Future<void> batchDownload(BuildContext context, ReaderHost host) async {
    if (ReadApi.isLocalBook(host.book)) {
      Toast.show('本地书籍无需缓存');
      return;
    }
    if (CacheBook.isRunning(host.book.bookUrl)) {
      Toast.show('已有缓存任务正在进行中');
      return;
    }
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择下载章节'),
        children: [
          for (final e in const [(20, '后20章'), (50, '后50章'), (100, '后100章'), (-1, '全部')])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.$1), child: Text(e.$2)),
        ],
      ),
    );
    if (n == null) return;
    final from = host.chapterIndex;
    final to = n < 0 ? host.chapters.length - 1 : from + n - 1;
    Toast.show('准备缓存...');
    final helper = DownNotificationHelper.instance;
    try {
      final r = await CacheBook(
        host.api,
        concurrent: Storage.getInt('cacheThread', 2).clamp(1, 8),
      ).cacheRange(from, to, onProgress: (done, total, _) => helper.update(DownTask(host.book.bookUrl, host.book.name, done, total)));
      helper.update(DownTask(host.book.bookUrl, host.book.name, r.cached.length, r.cached.length, finished: true, failed: r.failed.length));
      Toast.show('缓存加载完成');
    } catch (e) {
      Toast.show('$e');
    }
  }

  static Future<void> chapterUrl(BuildContext context, ReaderHost host) async {
    final c = host.chapters[host.chapterIndex];
    final url = c.baseUrl.isEmpty ? host.book.bookUrl : c.baseUrl;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('正文地址'),
        content: SelectableText(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Toast.show('地址已复制');
              Navigator.pop(ctx);
            },
            child: const Text('复制地址'),
          ),
        ],
      ),
    );
  }

  static Future<void> browser(BuildContext context, ReaderHost host) async {
    final c = host.chapters[host.chapterIndex];
    final url = c.baseUrl.isEmpty ? host.book.bookUrl : c.baseUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      Toast.show('无效的地址');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> refresh(BuildContext context, ReaderHost host) async {
    host.closeMenus();
    await host.reloadChapter(refresh: !ReadApi.isLocalBook(host.book));
    Toast.show('操作成功');
  }

  static Future<void> replacePurify(BuildContext context, ReaderHost host) async {
    host.book.useReplaceRule = !host.book.useReplaceRule;
    Toast.show(host.book.useReplaceRule ? '已开启替换净化' : '已关闭替换净化');
    await host.reloadChapter();
  }

  /// Ai净化 (0x95a13c -> 0x10e8814): switches the book's `useai` on the shelf (0x10e8aa8) and reloads the chapter; `ReadApi.purify` then
  /// sends chapters without a stored result to the purify model (at most `concurrent` at a time) and keeps the answer per chapter.
  static Future<void> aiPurify(BuildContext context, ReaderHost host) async {
    try {
      host.book.useai = !host.book.useai;
      await BookSelfN.setUseAi(host.book.bookUrl, host.book.useai);
      await host.reloadChapter();
      Toast.show('操作成功');
    } catch (e) {
      Toast.show('设置失败:$e');
    }
  }

  static Future<void> effectivePurify(BuildContext context, ReaderHost host) async {
    await ReplaceData.load();
    final rules = [
      ...ReplaceRuleEngine.select(ReplaceData.rules, host.book, title: false),
      ...ReplaceRuleEngine.select(ReplaceData.rules, host.book, title: true),
    ];
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('起效净化'),
        content: SizedBox(
          width: double.maxFinite,
          child: rules.isEmpty
              ? const Text('无')
              : ListView(
                  shrinkWrap: true,
                  children: [for (final r in rules) ListTile(dense: true, title: Text(r.name), subtitle: Text(r.pattern))],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReplaceRuleSetting()));
            },
            child: const Text('替换净化'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  static Future<void> highlightRule(BuildContext context, ReaderHost host) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HighlightRuleSetting()));
    host.closeMenus();
    await host.relayout();
  }

  /// 备份设置 (0x10e6c30): the non-empty prefs of [readerBackupKeys] as one JSON map, uploaded as cloud item `readitems`.
  static Future<void> backupSetting(BuildContext context, ReaderHost host) async {
    try {
      final map = <String, String>{
        for (final k in readerBackupKeys)
          if (Storage.getString(k).isNotEmpty) k: Storage.getString(k),
      };
      await TopMenuActions.uploadItem(cloudItem, jsonEncode(map));
      Toast.show('上传成功');
    } catch (e) {
      Toast.show('上传失败：$e');
    }
  }

  /// 恢复设置 (0x10e6874): downloads `readitems` and writes every string entry back to prefs ("您还没有备份" when absent).
  static Future<void> restoreSetting(BuildContext context, ReaderHost host) async {
    try {
      final text = await TopMenuActions.downloadItem(cloudItem);
      if (text.trim().isEmpty) {
        Toast.show('您还没有备份');
        return;
      }
      final map = jsonDecode(text);
      if (map is! Map) throw const FormatException('您还没有备份');
      for (final e in map.entries) {
        if (e.value is String) await Storage.setString('${e.key}', e.value as String);
      }
      host.setting.reload();
      await host.relayout();
      Toast.show('恢复成功');
    } catch (e) {
      Toast.show('恢复失败:$e');
    }
  }

  static Future<void> showLog(BuildContext context, ReaderHost host) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('显示日志'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(children: [for (final l in host.logs.reversed) Text(l, style: const TextStyle(fontSize: 12))]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
    ),
  );

  static Future<void> buyChapter(BuildContext context, ReaderHost host) async {
    final c = host.chapters[host.chapterIndex];
    if (!c.isPay) {
      Toast.show('当前章节无需购买');
      return;
    }
    final pay = TopMenu.payAction;
    if (pay == null) {
      Toast.show('购买失败: 当前书源不支持');
      return;
    }
    try {
      await pay(host.book, c);
      await host.reloadChapter(refresh: true);
    } catch (e) {
      Toast.show('购买失败: $e');
    }
  }
}

class TopMenu extends StatelessWidget {
  final ReaderHost host;
  const TopMenu({super.key, required this.host});

  /// Book-source `payAction` for 购买章节 (default: the book-source engine; the app may override it).
  static Future<void> Function(Book book, BookChapter chapter)? payAction = WebBookLoader.pay;

  static final Map<String, TopMenuEntry> entries = {
    for (final e in <TopMenuEntry>[
      TopMenuEntry('batchDownload', Icons.download_outlined, '批量下载', TopMenuActions.batchDownload),
      TopMenuEntry('sourceLogin', Icons.login, '书源登录', (c, h) => Nav.openNamed(c, 'source_login', arguments: h.book.origin)),
      TopMenuEntry('chapterUrl', Icons.link, '正文地址', TopMenuActions.chapterUrl),
      TopMenuEntry('bookmark', Icons.bookmark_border, '书签', (c, h) => h.toggleBookmark()),
      TopMenuEntry('searchContent', Icons.search, '搜索正文', (c, h) async => h.openSearch()),
      TopMenuEntry('aiPurify', Icons.auto_fix_high, 'Ai净化', TopMenuActions.aiPurify),
      TopMenuEntry('replacePurify', Icons.find_replace, '替换净化', TopMenuActions.replacePurify),
      TopMenuEntry('effectivePurify', Icons.rule, '起效净化', TopMenuActions.effectivePurify),
      TopMenuEntry('highlightRule', Icons.highlight, '高亮规则', TopMenuActions.highlightRule),
      TopMenuEntry('buyChapter', Icons.shopping_cart_outlined, '购买章节', TopMenuActions.buyChapter),
      TopMenuEntry('backupSetting', Icons.backup_outlined, '备份设置', TopMenuActions.backupSetting),
      TopMenuEntry('restoreSetting', Icons.settings_backup_restore, '恢复设置', TopMenuActions.restoreSetting),
      TopMenuEntry('browser', Icons.public, '用浏览器打开', TopMenuActions.browser),
      TopMenuEntry('changeSource', Icons.swap_horiz, '换源', (c, h) => Nav.openNamed(c, 'book_change_yuan', arguments: h.book)),
      TopMenuEntry('refresh', Icons.refresh, '刷新', TopMenuActions.refresh),
      TopMenuEntry('showLog', Icons.article_outlined, '显示日志', TopMenuActions.showLog),
    ])
      e.id: e,
  };

  @override
  Widget build(BuildContext context) {
    final ids = Setting.getTopMenuButtons();
    final scheme = Theme.of(context).colorScheme;
    final local = ReadApi.isLocalBook(host.book);
    return QGlassContainer(
      borderRadius: 0,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Nav.openBook(context, host.book),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(host.book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                        Text(
                          host.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
                // 定制按钮 of a 时光源 (0x10e950c / 0x10e93c4): tap clickCustomButton, long press longClickCustomButton
                if (!local && SourceEvents.hasCustomButton(host.book.origin))
                  InkResponse(
                    key: const Key('reader_custom_button'),
                    radius: 22,
                    onTap: () => SourceEvents.send(host.book.origin, SourceEvents.clickCustomButton, host.book),
                    onLongPress: () => SourceEvents.send(host.book.origin, SourceEvents.longClickCustomButton, host.book),
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.circle_outlined)),
                  ),
                for (final id in ids)
                  if (entries[id] != null && !(local && const {'browser', 'changeSource', 'sourceLogin', 'buyChapter'}.contains(id)))
                    id == 'bookmark'
                        ? _BookmarkButton(host: host)
                        : IconButton(
                            tooltip: entries[id]!.label,
                            icon: Icon(entries[id]!.icon),
                            onPressed: () => entries[id]!.run(context, host),
                          ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (id) {
                    if (id == 'detail') {
                      Nav.openBook(context, host.book);
                      return;
                    }
                    entries[id]?.run(context, host);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'detail', child: Text('详情')),
                    for (final e in entries.values)
                      if (!ids.contains(e.id)) PopupMenuItem(value: e.id, child: Text(e.label)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookmarkButton extends StatefulWidget {
  final ReaderHost host;
  const _BookmarkButton({required this.host});

  @override
  State<_BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<_BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final on = widget.host.isBookmarked;
    return IconButton(
      tooltip: '书签',
      icon: Icon(on ? Icons.bookmark : Icons.bookmark_border),
      onPressed: () async {
        await widget.host.toggleBookmark();
        if (mounted) setState(() {});
      },
    );
  }
}
