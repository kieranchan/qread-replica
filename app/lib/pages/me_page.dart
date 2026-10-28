// pages/me_page.dart — 「我的」 (`MePage`, state `_MePageState`, build 0x514204). Layout of the original, top to bottom:
//   app bar `我的` + theme-mode button (prefs `dark`, 0xe13f4 / ThemeProvider.setThemeMode)
//   user card (0x51dfec): avatar (`lib/assets/images/me.png` fallback), nickname or `立即登录` (→ LoginPage / UserSettingPage),
//     `今日阅读 n分钟` / `今日还没有读过书哦` (→ ReadingStatisticsPage 0x51f3d4), 每日目标 n/m 分钟 → `目标达成`
//     (`_editDailyReadingGoal` 0x51ee98, prefs `dailyReadingGoal`, card hidden by `showDailyGoal`)
//   member card (0x51dac0): signed out `登录同步阅读进度` + `立即登录`; non-member `立即开通`; member `会员中心` (vip text contains
//     `永久`) or `立即续费` (0x51df28) → `openMemberCenter()` (WebView `vip?tockenid=`, then `UserSession.refresh()`, 0xf64c88)
//   quick row (0x51b83c): 主题管理 (→ FontSettingPage 主题设置), 字体管理, 阅读背景, 历史记录
//   recent reading (0x5191c8, prefs `showRecentRead`): last read books, `暂无阅读记录` / `开始阅读一本好书吧`
//   tools (0x517f18 / taps 0x51898c): 书源管理 朗读引擎 替换净化 高亮规则 目录规则 网盘管理 背景音乐 浏览器 下载管理
//   settings (0x514f18 / taps 0x515c90): 阅读设置 书源设置 听书设置 (快捷按键 on desktop) 备份管理 反馈问题 联系我们 清除缓存 关于我们
// Replica additions kept from phase 1: 云端设置 (`me_cloud`) and 诊断自检 (`me_self_check`), plus AI模型配置 / Wi-Fi传书 entries so
// every extras page is reachable. Pages of other areas open through `Nav.openNamed` (common/nav.dart).
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/common.dart';
import '../common/nav.dart';
import '../data/bookself.dart';
import '../data/user.dart';
import '../models/book.dart';
import '../storage/book_reading_time_storage.dart';
import '../storage/storage.dart';
import '../theme/theme_provider.dart';
import '../theme/widgets.dart';
import '../widget/ui/q_glass.dart';
import '../util/toast.dart';
import 'about_page.dart';
import 'background_manager_page.dart';
import 'fonts/fouts_setting.dart';
import 'login_page.dart';
import 'reading_statistics_page.dart';
import 'self_check_page.dart';
import 'setting/ai_model_page.dart';
import 'setting/background_music_page.dart';
import 'setting/backup_page.dart';
import 'setting/clean_page.dart';
import 'setting/hotkey_setting_page.dart';
import 'setting/listem_setting_page.dart';
import 'setting/search_setting_page.dart';
import 'theme/font_setting_page.dart';
import 'tts/tts_setting.dart';
import 'user/cloud_setting_page.dart';
import 'user/user_edit_page.dart';
import 'user/user_setting_page.dart';
import 'web/nwebview.dart';
import 'webdav/webdav_manager_page.dart';
import 'wifi_page.dart';

/// Opens the membership page exactly like the original (`vip?tockenid=` appended to the base), then refreshes the account.
Future<void> openMemberCenter() async {
  await Get.to(() => NWebviewPage(url: '${Common.apiBase}vip?tockenid=${UserSession.tockenid}', title: '会员中心'));
  await UserSession.refresh();
}

class MePage extends StatefulWidget {
  const MePage({super.key});

  static const String dailyGoalKey = 'dailyReadingGoal';
  static const String showDailyGoalKey = 'showDailyGoal';
  static const String showRecentReadKey = 'showRecentRead';

  /// Default goal in minutes when nothing is stored (0x10be2a8 → closure 0x8ebf9c: `int.tryParse(dailyReadingGoal) ?? 30`).
  static const int defaultGoal = 30;

  static int get dailyGoal => int.tryParse(Storage.getString(dailyGoalKey).trim()) ?? defaultGoal;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  static const String page = 'me';
  int _todayMinutes = 0;

  bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _loadToday();
    BookSelfN.revision.addListener(_onShelf);
  }

  @override
  void dispose() {
    BookSelfN.revision.removeListener(_onShelf);
    super.dispose();
  }

  void _onShelf() {
    if (mounted) setState(() {});
  }

  Future<void> _loadToday() async {
    try {
      final s = await BookReadingTimeStorage.daySeconds(DateTime.now());
      if (mounted) setState(() => _todayMinutes = s ~/ 60);
    } catch (_) {}
  }

  Future<void> _go(Widget Function() page) async {
    await Get.to(page);
    _loadToday();
    if (mounted) setState(() {});
  }

  Future<void> _named(String name) => Nav.openNamed(context, name);

  // ------------------------------------------------------------------------------------------------ cards

  Widget _userCard() {
    final cs = Theme.of(context).colorScheme;
    final logged = UserSession.isLoggedIn;
    final avatar = logged && UserSession.avatarUrl.isNotEmpty
        ? NetworkImage(UserSession.avatarUrl) as ImageProvider
        : const AssetImage('lib/assets/images/me.png');
    final goal = MePage.dailyGoal;
    final showGoal = Storage.getBool(MePage.showDailyGoalKey, true);
    final reached = _todayMinutes >= goal;
    return SectionCard(page: page, children: [
      InkWell(
        key: const Key('me_account'),
        onTap: () => logged ? _go(() => const UserSettingPage()) : _go(() => const LoginPage()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => logged ? _go(() => const UserEditPage()) : _go(() => const LoginPage()),
              child: CircleAvatar(radius: 30, backgroundImage: avatar, onBackgroundImageError: (_, _) {}),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(logged ? UserSession.nickname : '立即登录', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(logged ? UserSession.vipLabel : '登录同步阅读数据', style: TextStyle(fontSize: 13, color: cs.outline)),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.outline),
          ]),
        ),
      ),
      InkWell(
        key: const Key('me_today'),
        onTap: () => _go(() => const ReadingStatisticsPage()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            Icon(Icons.timer_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(_todayMinutes > 0 ? '今日阅读 $_todayMinutes分钟' : '今日还没有读过书哦', style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: cs.outline),
          ]),
        ),
      ),
      if (showGoal)
        InkWell(
          key: const Key('me_goal'),
          onTap: _editDailyReadingGoal,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(reached ? Icons.emoji_events_outlined : Icons.flag_outlined, size: 16, color: reached ? Colors.orange : cs.primary),
                const SizedBox(width: 6),
                Text(reached ? '目标达成' : '每日目标', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_todayMinutes.clamp(0, 9999)}/$goal 分钟', style: TextStyle(fontSize: 12, color: cs.outline)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: goal == 0 ? 0 : (_todayMinutes / goal).clamp(0, 1).toDouble(), minHeight: 6),
              ),
            ]),
          ),
        ),
    ]);
  }

  /// 0x51ef4c: minutes, digits only.
  Future<void> _editDailyReadingGoal() async {
    final v = await Dialogs.input(context, '每日目标', initial: '${MePage.dailyGoal}', hint: '分钟', keyboardType: TextInputType.number);
    if (v == null) return;
    final n = int.tryParse(v.trim());
    if (n == null || n <= 0) return;
    await Storage.setString(MePage.dailyGoalKey, '$n');
    if (mounted) setState(() {});
  }

  Widget _memberCard() {
    final logged = UserSession.isLoggedIn;
    final vip = UserSession.isvip;
    final forever = UserSession.vipText.contains('永久');
    final String text;
    final String button;
    if (!logged) {
      text = '登录同步阅读进度';
      button = '立即登录';
    } else if (!vip) {
      text = '开通会员，解锁全部功能';
      button = '立即开通';
    } else {
      text = forever ? '永久会员' : '会员有效期：${UserSession.vipText}';
      button = forever ? '会员中心' : '立即续费';
    }
    const gold = Color(0xFF8B6914);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [Color(0xFFFFE9B0), Color(0xFFF7D27A)]),
      ),
      child: InkWell(
        key: logged ? const Key('me_member') : const Key('me_member_login'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (!logged) return _go(() => const LoginPage());
          await openMemberCenter();
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Icon(Icons.workspace_premium, color: gold),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: gold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(16)),
              child: Text(button, style: const TextStyle(fontSize: 13, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _grid(List<(IconData, String, Key?, VoidCallback)> items, {String? title}) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 4) {
      final chunk = items.sublist(i, i + 4 > items.length ? items.length : i + 4);
      rows.add(Row(children: [
        for (final it in chunk)
          Expanded(
            child: InkWell(
              key: it.$3,
              onTap: it.$4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Icon(it.$1, size: 26, color: cs.primary),
                  const SizedBox(height: 6),
                  Text(it.$2, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
        for (var k = chunk.length; k < 4; k++) const Expanded(child: SizedBox()),
      ]));
    }
    return SectionCard(page: page, title: title, children: rows);
  }

  Widget _recent() {
    if (!Storage.getBool(MePage.showRecentReadKey, true)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final books = [...Bookdata.books.where((b) => b.durChapterTime > 0)]..sort((a, b) => b.durChapterTime.compareTo(a.durChapterTime));
    final list = books.take(10).toList();
    return SectionCard(page: page, title: '最近阅读', children: [
      SizedBox(
        height: 160,
        child: list.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_stories_outlined, size: 30, color: cs.outline),
                  const SizedBox(height: 6),
                  const Text('暂无阅读记录', style: TextStyle(fontSize: 14)),
                  Text('开始阅读一本好书吧', style: TextStyle(fontSize: 12, color: cs.outline)),
                ]),
              )
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: list.length,
                itemBuilder: (_, i) => _bookTile(list[i]),
              ),
      ),
    ]);
  }

  Widget _bookTile(Book b) {
    final cover = b.coverUrl.startsWith('http')
        ? Image.network(b.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Image.asset('lib/assets/images/no_cover.jpeg', fit: BoxFit.cover))
        : Image.asset('lib/assets/images/no_cover.jpeg', fit: BoxFit.cover);
    return GestureDetector(
      onTap: () async {
        if (!BookSelfN.contains(b.bookUrl)) return Toast.show('当前书本已被删除');
        await Nav.openReader(context, b);
        _loadToday();
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 80, height: 104, child: cover)),
          const SizedBox(height: 4),
          Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          Text(b.durChapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ dialogs

  /// 反馈问题 (0x516354 / 0x516414): text box, 提交 opens the mail app with subject `轻悦时光的问题`.
  Future<void> _feedback() async {
    final text = await Dialogs.input(context, '问题反馈', hint: '请输入您的问题或建议...', maxLines: 5);
    if (text == null || text.trim().isEmpty) return;
    // TODO(asm 0x516414): the original mails its operator's support address; deliberately not copied (own server only), the recipient
    // stays empty.
    final uri = Uri(scheme: 'mailto', query: 'subject=${Uri.encodeComponent('轻悦时光的问题')}&body=${Uri.encodeComponent(text)}');
    try {
      if (!await launchUrl(uri)) throw StateError('mailto');
      Toast.show('感谢您的反馈，我们会尽快处理！');
    } catch (_) {
      Toast.show('邮箱打开失败', iserror: true);
    }
  }

  /// 联系我们 (0x516d6c): community groups from `static/qq.json` (a name → number map), tap copies the number.
  Future<void> _contact() async {
    Map<String, String> groups = {};
    try {
      final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)))
          .get<String>(Common.url('static/qq.json'), options: Options(responseType: ResponseType.plain));
      final v = jsonDecode(r.data ?? '');
      if (v is Map) groups = {for (final e in v.entries) '${e.key}': '${e.value}'};
    } catch (e) {
      Toast.show('获取QQ群信息失败: $e', iserror: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('官方QQ群'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('加入QQ群与其他读者交流，获取最新更新信息'),
          const SizedBox(height: 8),
          for (final e in groups.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.key.isEmpty ? '轻悦时光交流群' : e.key),
              subtitle: Text(e.value),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () {
                Clipboard.setData(ClipboardData(text: e.value));
                Toast.show('QQ群号已复制到剪贴板');
              },
            ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([UserSession.revision, ThemeProvider.instance]),
      builder: (context, _) {
        final tp = ThemeProvider.instance;
        final logged = UserSession.isLoggedIn;
        return StyledScaffold(
          page: page,
          appBar: AppBar(
            title: const Text('我的', style: TextStyle(fontWeight: FontWeight.w600)),
            centerTitle: false,
            // 0x514204: the actions sit in a glass pill (QGlassContainer, height 40, radius 20, horizontal padding 10) + 10 px gap.
            actions: [
              QGlassContainer(
                height: 40,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Tooltip(
                    message: '跟随系统 / 白天 / 夜间',
                    child: GestureDetector(key: const Key('me_dark'), onTap: tp.cycleMode, child: Icon(tp.modeIcon, size: 24)),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await UserSession.refresh();
              await _loadToday();
            },
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(bottom: 60), children: [
              _userCard(),
              _memberCard(),
              _grid([
                (Icons.cloud_outlined, '云端设置', const Key('me_cloud'), () => logged ? _go(() => const CloudSettingPage()) : _go(() => const LoginPage())),
                (Icons.health_and_safety_outlined, '诊断自检', const Key('me_self_check'), () => _go(() => const SelfCheckPage())),
                (Icons.bar_chart_outlined, '阅读统计', const Key('me_stats'), () => _go(() => const ReadingStatisticsPage())),
                (Icons.wifi_outlined, 'Wi-Fi传书', const Key('me_wifi'), () => _go(() => const WiFiPage())),
              ]),
              _grid([
                (Icons.palette_outlined, '主题管理', const Key('me_theme'), () => _go(() => const FontSettingPage())),
                (Icons.font_download_outlined, '字体管理', const Key('me_fonts'), () => _go(() => const FontsSetting())),
                (Icons.wallpaper_outlined, '阅读背景', const Key('me_bg'), () => _go(() => const BackgroundManagerPage())),
                (Icons.history, '历史记录', const Key('me_history'), () => _named('history_page')),
              ]),
              _recent(),
              _grid(title: '工具', [
                (Icons.source_outlined, '书源管理', null, () => _named('source_page')),
                (Icons.record_voice_over_outlined, '朗读引擎', const Key('me_tts'), () => _go(() => const TTsSetting())),
                (Icons.find_replace_outlined, '替换净化', null, () => _named('replace_page')),
                (Icons.highlight_outlined, '高亮规则', null, () => _named('highlight_page')),
                (Icons.format_list_numbered, '目录规则', null, () => _named('txtrule_page')),
                (Icons.cloud_queue_outlined, '网盘管理', const Key('me_webdav'), () => _go(() => const WebDavManagerPage())),
                (Icons.music_note_outlined, '背景音乐', const Key('me_music'), () => _go(() => const BackgroundMusicPage())),
                (Icons.public, '浏览器', null, () => _named('chrome_inapp')),
                (Icons.download_outlined, '下载管理', null, () => _named('download_manager_page')),
              ]),
              _grid(title: '设置', [
                (Icons.menu_book_outlined, '阅读设置', null, () => _named('read_setting_page')),
                (Icons.tune, '书源设置', const Key('me_search_setting'), () => _go(() => const SeachSettingPage())),
                if (_desktop)
                  (Icons.keyboard_outlined, '快捷按键', const Key('me_hotkey'), () => _go(() => const HotkeySettingPage()))
                else
                  (Icons.headphones_outlined, '听书设置', const Key('me_listen'), () => _go(() => const ListenSettingPage())),
                (Icons.smart_toy_outlined, 'AI模型配置', const Key('me_ai'), () => _go(() => const AiModelPage())),
                (Icons.backup_outlined, '备份管理', const Key('me_backup'), () => _go(() => const BackupPage())),
                (Icons.feedback_outlined, '反馈问题', null, _feedback),
                (Icons.groups_outlined, '联系我们', null, _contact),
                (Icons.cleaning_services_outlined, '清除缓存', const Key('me_clean'), () => _go(() => const CleanPage())),
                (Icons.info_outline, '关于我们', const Key('me_about'), () => _go(() => const AboutPage())),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
