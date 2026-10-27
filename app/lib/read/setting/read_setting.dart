// read/setting/read_setting.dart — `ReadSetting`: every reader preference, read from and written to SharedPreferences.
//
// Original: class 1476 `ReadSetting` (0x320 bytes) owned by `_NovelViewState.setting`; its loader 0x10c71c0 calls one thin getter per
// prefs key (0x664270 paragraphSpacing, 0x6645a8 lineHeight, 0x66452c letterSpacing, 0x2b39b0 fontFamily, 0x663c48/0x663c0c/0x663bc0
// underline*, 0x2b3a24 font size, 0x2279ac ispad, 0x663b74 showTop, 0x663b28 showBottom, 0x664440 topMargin ... 0x6644b4
// fontWeight12345). Every value is a String in prefs (docs/SETTINGS.md). The "排版" presets of the bottom menu are `BackGround` objects
// (`Ground.grounds`); applying one copies its layout fields into these prefs ([applyLayout]).
//
// Background colours (0x2460c4 / 0x245b64 / 0x245728): the selected style id is `background` (day) or `darkbackground` (night, default
// `4`); ids below `Common.background.length` are the built-in colours `#e6e6e6 #c4b395 #cad9e8 #d1edd1 #000000 #ffffff` (text colour
// `Colors.white70` on `#000000`, otherwise `Colors.black87`), larger ids name a `BackGround` of `Ground.grounds`.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../common/common.dart';
import '../../data/ground.dart';
import '../../models/back_ground.dart';
import '../../pages/read/pages/novel/views/turn.dart';
import '../../storage/storage.dart';
import 'read_layout_style.dart';

/// Page-turn modes (`turn`, map 0x96fc54).
abstract class TurnMode {
  static const int cover = 0; // 左右覆盖
  static const int slide = 1; // 左右平移
  static const int verticalSlide = 2; // 上下平移
  static const int none = 3; // 无动画
  static const int scroll = 4; // 上下滚动
  static const int simulation = 5; // 仿真翻页
  static const int book = 6; // 模拟翻书
  static const int appleBook = 7; // 仿真翻页(IOS原生), only offered on iOS

  /// 0x96fc54: the list the bottom menu offers (the iOS build adds [appleBook]).
  static Map<int, String> labels({bool ios = false}) => {
        cover: '左右覆盖',
        simulation: '仿真翻页',
        if (ios) appleBook: '仿真翻页(IOS原生)',
        book: '模拟翻书',
        slide: '左右平移',
        verticalSlide: '上下平移',
        scroll: '上下滚动',
        none: '无动画',
      };
}

/// `showProgress` values (read_more_setting: 不显示 · 章节进度 · 全文进度 · 章节进度和全文进度).
abstract class ProgressMode {
  static const int hidden = 0;
  static const int chapter = 1;
  static const int book = 2;
  static const int both = 3;
}

/// `simplified1` values (bottom menu 简体繁体: 原文 / 简体 / 繁体). 0x24d448 converts with `ChineseUtils`: 1 = to simplified, 2 = to
/// traditional, and leaves chapters longer than 100000 characters as they are ("正本内容过长，暂不支持简繁转换").
abstract class FanMode {
  static const int off = 0;
  static const int toSimplified = 1;
  static const int toTraditional = 2;

  static const int maxLength = 100000;
}

/// The items of a custom header / footer slot (`customHeaderLeft` ... `customFooterRight` are JSON lists of these ids; names pp+0x72a78).
abstract class SlotItem {
  static const int time = 0;
  static const int batteryInside = 1;
  static const int batteryOutside = 2;
  static const int chapterProgress = 3;
  static const int bookProgress = 4;
  static const int title = 5;
  static const int bookName = 6;

  static const List<String> names = ['时间', '内置百分比电池', '外置百分比电池', '章节进度', '全文进度', '标题', '书名'];
}

/// `fen` (更多设置 "分割线": 不显示 / 页眉 / 页脚 / 页眉和页脚): a line under the header and / or above the footer.
abstract class DividerMode {
  static const int none = 0;
  static const int header = 1;
  static const int footer = 2;
  static const int both = 3;
}

/// `wakelockTimeout` (屏幕常亮; 0x2b4e64): 0 跟随系统, 1 / 2 / 5 / 10 minutes after the last activity, -1 常亮 (the default).
abstract class WakeMode {
  static const int system = 0;
  static const int always = -1;
  static const Map<int, String> labels = {0: '跟随系统', 1: '1分钟', 2: '2分钟', 5: '5分钟', 10: '10分钟', -1: '常亮'};

  /// Seconds of inactivity before the screen may sleep again (0 = no timer).
  static int seconds(int option) => switch (option) { 1 => 60, 2 => 120, 5 => 300, 10 => 600, _ => 0 };
}

/// The colours the reader paints with (original class `ReadConfig`, built by 0xecc920).
class ReadConfig {
  final Color backgroundColor;
  final Color textColor;
  final DecorationImage? image;
  final Color? readColor;
  final Color? menuColor;
  final Color? menuTextColor;

  const ReadConfig({required this.backgroundColor, required this.textColor, this.image, this.readColor, this.menuColor, this.menuTextColor});

  bool get isDark => backgroundColor.computeLuminance() < 0.25;

  BoxDecoration get decoration => BoxDecoration(color: backgroundColor, image: image);

  /// The colour of the text being read aloud (`BackGround.readColor`, else a blue that works on both themes).
  Color get speakColor => readColor ?? (isDark ? const Color(0xFF7DB4FF) : const Color(0xFF1565C0));
}

class ReadSetting extends ChangeNotifier {
  // ------------------------------------------------------------------ built-in backgrounds

  /// `Common.background` initializer 0x245ad8.
  static const List<String> builtinColors = ['#e6e6e6', '#c4b395', '#cad9e8', '#d1edd1', '#000000', '#ffffff'];

  /// `Common.backgroundimages` (0x6627ec): `lib/assets/bg/1.jpg` .. `14.jpg`.
  static final List<String> builtinImages = [for (var i = 1; i <= 14; i++) 'lib/assets/bg/$i.jpg'];

  /// Ids `builtinColors.length ..` select a built-in image. TODO(asm 0x10162d4): the original id layout of the image swatches is not
  /// recovered; user styles use ids from [userIdBase] up.
  static int get imageIdBase => builtinColors.length;
  static int get userIdBase => builtinColors.length + builtinImages.length;

  /// The font-size key: static 0x2240 (`"fontSize"`) + `"default"` (getter 0x2b3b4c, setter 0xfa2de0; the static's initial value is
  /// in the snapshot's field table). A plain int, default 30, clamped to 10..55 by 0x2b3a24.
  static const String fontSizeKey = 'fontSizedefault';

  /// The six custom header / footer slots and their values when the key is absent (getters 0x1010228 / 0x1010100 / 0x100ffd8 /
  /// 0x1010630 / 0x10104d8 / 0x1010380): header 标题 | - | -, footer 时间 | 章节进度 | 外置百分比电池.
  static const Map<String, List<int>> slotDefaults = {
    'customHeaderLeft': [SlotItem.title],
    'customHeaderCenter': [],
    'customHeaderRight': [],
    'customFooterLeft': [SlotItem.time],
    'customFooterCenter': [SlotItem.chapterProgress],
    'customFooterRight': [SlotItem.batteryOutside],
  };

  /// Called when the reader switches day/night so the app theme can follow (wired by the lead; null = reader only).
  static void Function(bool night)? onNightChanged;

  static void ensureBuiltins() {
    if (Common.background.isEmpty) Common.background = List<String>.of(builtinColors);
    if (Common.backgroundimages.isEmpty) Common.backgroundimages = List<String>.of(builtinImages);
  }

  ReadSetting() {
    ensureBuiltins();
    reload();
  }

  // ------------------------------------------------------------------ values

  int turn = TurnMode.cover;
  int pageTurnSpeed = 300;
  bool volumeButton = true;
  ClickAreaSetting clickArea = ClickAreaSetting.defaults();
  int turntime = 10;
  int turnsudu = 1;

  /// 翻页距离 of the auto-turn bar (`fan`, 0x8f7f40 default 5, slider up to 200).
  int fan = 5;

  /// 简体繁体 (`simplified1`, [FanMode]).
  int simplified = FanMode.off;

  /// 菜单滑动条 按章节 (0) / 按分页 (1) (`menuSliderType`).
  int menuSliderType = 0;

  /// The custom header / footer slots ([slotDefaults]).
  Map<String, List<int>> slots = {for (final e in slotDefaults.entries) e.key: List<int>.of(e.value)};

  int fontSize = 30;
  double lineHeight = 2;
  double letterSpacing = 1;
  int fontWeight = 400;
  String fontFamily = '';
  double paragraphSpacing = 10;
  int kong = 2;
  int fen = 0;
  int titleAlign = 0;
  int titleTopMargin = 0;
  int titleBottomMargin = 0;
  int titlefontSize = 7;
  int topMargin = 5;
  int bottomMargin = 0;
  int leftMargin = 16;
  int rightMargin = 16;
  int safeTop = -1;
  int safeBottom = -1;
  int headerLeftMargin = 16;
  int headerRightMargin = 16;
  int footerLeftMargin = 16;
  int footerRightMargin = 16;
  int headerFooterFontSize = 12;
  bool underline = false;
  int underlineStyle = 0;
  bool underlineFullWidth = true;
  bool showTop = true;
  bool showBottom = true;
  bool ispad = false;
  bool needdp = true;

  bool hidetitle = false;
  bool hidetop = true;
  bool hidebottom = true;
  int showProgress = ProgressMode.chapter;
  int background = 0;
  int darkbackground = 4;
  bool night = false;
  double brightness = -1;
  bool autoBrightness = true;
  int wakelockTimeout = -1;
  bool lock = true;
  int readHighlightType = 1;
  bool aichat = true;
  bool needcss2 = true;
  bool bottomfix = true;
  bool downmark = false;
  bool exit = false;
  bool fullNext = true;
  bool reverseCatalog = false;

  /// Reloads everything from prefs.
  void reload() {
    turn = Storage.getInt('turn', TurnMode.cover).clamp(0, 7);
    pageTurnSpeed = Storage.getInt('pageTurnSpeed', 300).clamp(100, 1000);
    volumeButton = Storage.getBool('volumeButton', true);
    clickArea = ClickAreaSetting.load();
    final tt = Storage.getInt('turntime');
    turntime = tt <= 0 ? 10 : tt;
    turnsudu = Storage.getInt('turnsudu', 1).clamp(1, 20);
    fan = Storage.getInt('fan', 5).clamp(1, 200);
    simplified = Storage.getInt('simplified1').clamp(0, 2);
    menuSliderType = Storage.getInt('menuSliderType').clamp(0, 1);
    for (final k in slotDefaults.keys) {
      slots[k] = slot(k);
    }

    fontSize = Storage.getInt(fontSizeKey, 30).clamp(10, 55);
    final lh = Storage.getDouble('lineHeight');
    lineHeight = lh == 0 ? 2 : lh.clamp(1, 4);
    letterSpacing = Storage.getDouble('letterSpacing', 1);
    fontWeight = Storage.getInt('fontWeight12345', 400).clamp(100, 900);
    fontFamily = Storage.getString('fontFamily');
    paragraphSpacing = Storage.getDouble('paragraphSpacing', 10).clamp(0, 100);
    kong = Storage.getInt('kong', 2).clamp(0, 8);
    fen = Storage.getInt('fen').clamp(0, 3);
    titleAlign = Storage.getInt('titleAlign').clamp(0, 2);
    titleTopMargin = Storage.getInt('titleTopMargin').clamp(0, 200);
    titleBottomMargin = Storage.getInt('titleBottomMargin').clamp(0, 200);
    titlefontSize = Storage.getInt('titlefontSize', 7);
    topMargin = Storage.getInt('topMargin', 5).clamp(0, 200);
    bottomMargin = Storage.getInt('bottomMargin').clamp(0, 200);
    leftMargin = Storage.getInt('leftMargin', 16).clamp(0, 200);
    rightMargin = Storage.getInt('rightMargin', 16).clamp(0, 200);
    safeTop = Storage.getInt('safeTop', -1);
    safeBottom = Storage.getInt('safeBottom', -1);
    headerLeftMargin = Storage.getInt('headerLeftMargin', 16);
    headerRightMargin = Storage.getInt('headerRightMargin', 16);
    footerLeftMargin = Storage.getInt('footerLeftMargin', 16);
    footerRightMargin = Storage.getInt('footerRightMargin', 16);
    headerFooterFontSize = Storage.getInt('headerFooterFontSize', 12).clamp(8, 30);
    underline = Storage.getBool('underline');
    underlineStyle = Storage.getInt('underlineStyle');
    underlineFullWidth = Storage.getBool('underlineFullWidth', true);
    showTop = Storage.getBool('showTop', true);
    showBottom = Storage.getBool('showBottom', true);
    ispad = Storage.getBool('ispad');
    needdp = Storage.getBool('needdp', true);

    hidetitle = Storage.getBool('hidetitle');
    hidetop = Storage.getBool('hidetop', true);
    hidebottom = Storage.getBool('hidebottom', true);
    showProgress = Storage.getInt('showProgress', ProgressMode.chapter).clamp(0, 3);
    background = math.max(0, Storage.getInt('background'));
    darkbackground = math.max(0, Storage.getInt('darkbackground', 4));
    brightness = Storage.getDouble('brightness', -1);
    autoBrightness = Storage.getBool('autoBrightness', true);
    wakelockTimeout = Storage.getInt('wakelockTimeout', -1);
    lock = Storage.getBool('lock', true);
    readHighlightType = Storage.getInt('readHighlightType', 1);
    aichat = Storage.getBool('aichat', true);
    needcss2 = Storage.getBool('needcss2', true);
    bottomfix = Storage.getBool('bottomfix', true);
    downmark = Storage.getBool('downmark');
    exit = Storage.getBool('exit');
    fullNext = Storage.getBool('fullNext', true);
  }

  // ------------------------------------------------------------------ writers (each persists and notifies)

  Future<void> _setInt(String key, int v) async {
    await Storage.setInt(key, v);
    notifyListeners();
  }

  Future<void> _setDouble(String key, double v) async {
    await Storage.setDouble(key, v);
    notifyListeners();
  }

  Future<void> _setBool(String key, bool v) async {
    await Storage.setBool(key, v);
    notifyListeners();
  }

  Future<void> setTurn(int v) {
    turn = v;
    return _setInt('turn', v);
  }

  Future<void> setPageTurnSpeed(int v) {
    pageTurnSpeed = v.clamp(100, 1000);
    return _setInt('pageTurnSpeed', pageTurnSpeed);
  }

  Future<void> setVolumeButton(bool v) {
    volumeButton = v;
    return _setBool('volumeButton', v);
  }

  Future<void> setClickArea(ClickAreaSetting v) async {
    clickArea = v.copy();
    await v.save();
    notifyListeners();
  }

  Future<void> setTurntime(int v) {
    turntime = math.max(1, v);
    return _setInt('turntime', turntime);
  }

  Future<void> setTurnsudu(int v) {
    turnsudu = v.clamp(1, 20);
    return _setInt('turnsudu', turnsudu);
  }

  Future<void> setFontSize(int v) {
    fontSize = v.clamp(10, 55);
    return _setInt(fontSizeKey, fontSize);
  }

  Future<void> setLineHeight(double v) {
    lineHeight = double.parse(v.clamp(1, 4).toStringAsFixed(2));
    return _setDouble('lineHeight', lineHeight);
  }

  Future<void> setLetterSpacing(double v) {
    letterSpacing = double.parse(v.clamp(-2, 10).toStringAsFixed(2));
    return _setDouble('letterSpacing', letterSpacing);
  }

  Future<void> setParagraphSpacing(double v) {
    paragraphSpacing = v.clamp(0, 100).roundToDouble();
    return _setDouble('paragraphSpacing', paragraphSpacing);
  }

  Future<void> setFontWeight(int v) {
    fontWeight = v.clamp(100, 900);
    return _setInt('fontWeight12345', fontWeight);
  }

  Future<void> setFontFamily(String v) async {
    fontFamily = v;
    await Storage.setString('fontFamily', v);
    notifyListeners();
  }

  Future<void> setKong(int v) {
    kong = v.clamp(0, 8);
    return _setInt('kong', kong);
  }

  Future<void> setFen(int v) {
    fen = v.clamp(0, 3);
    return _setInt('fen', fen);
  }

  Future<void> setMargins({int? top, int? bottom, int? left, int? right}) async {
    if (top != null) {
      topMargin = top.clamp(0, 200);
      await Storage.setInt('topMargin', topMargin);
    }
    if (bottom != null) {
      bottomMargin = bottom.clamp(0, 200);
      await Storage.setInt('bottomMargin', bottomMargin);
    }
    if (left != null) {
      leftMargin = left.clamp(0, 200);
      await Storage.setInt('leftMargin', leftMargin);
    }
    if (right != null) {
      rightMargin = right.clamp(0, 200);
      await Storage.setInt('rightMargin', rightMargin);
    }
    notifyListeners();
  }

  Future<void> setTitle({int? align, int? top, int? bottom, int? size}) async {
    if (align != null) {
      titleAlign = align.clamp(0, 2);
      await Storage.setInt('titleAlign', titleAlign);
    }
    if (top != null) {
      titleTopMargin = top.clamp(0, 200);
      await Storage.setInt('titleTopMargin', titleTopMargin);
    }
    if (bottom != null) {
      titleBottomMargin = bottom.clamp(0, 200);
      await Storage.setInt('titleBottomMargin', titleBottomMargin);
    }
    if (size != null) {
      titlefontSize = size.clamp(-10, 30);
      await Storage.setInt('titlefontSize', titlefontSize);
    }
    notifyListeners();
  }

  Future<void> setHeaderFooter({bool? top, bool? bottom}) async {
    if (top != null) {
      showTop = top;
      await Storage.setBool('showTop', top);
    }
    if (bottom != null) {
      showBottom = bottom;
      await Storage.setBool('showBottom', bottom);
    }
    notifyListeners();
  }

  Future<void> setHidetitle(bool v) {
    hidetitle = v;
    return _setBool('hidetitle', v);
  }

  Future<void> setHidetop(bool v) {
    hidetop = v;
    return _setBool('hidetop', v);
  }

  Future<void> setHidebottom(bool v) {
    hidebottom = v;
    return _setBool('hidebottom', v);
  }

  Future<void> setShowProgress(int v) {
    showProgress = v.clamp(0, 3);
    return _setInt('showProgress', showProgress);
  }

  Future<void> setFan(int v) {
    fan = v.clamp(1, 200);
    return _setInt('fan', fan);
  }

  Future<void> setSimplified(int v) {
    simplified = v.clamp(0, 2);
    return _setInt('simplified1', simplified);
  }

  Future<void> setMenuSliderType(int v) {
    menuSliderType = v.clamp(0, 1);
    return _setInt('menuSliderType', menuSliderType);
  }

  /// A custom slot as the original reads it: the JSON list of item ids, or the default when the key is empty.
  static List<int> slot(String key) {
    final text = Storage.getString(key);
    if (text.isEmpty) return List<int>.of(slotDefaults[key] ?? const []);
    try {
      final v = jsonDecode(text);
      if (v is List) return [for (final e in v) if (e is num) e.toInt()];
    } catch (_) {}
    return [];
  }

  Future<void> setSlot(String key, List<int> items) async {
    slots[key] = List<int>.of(items);
    await Storage.setString(key, jsonEncode(items));
    notifyListeners();
  }

  Future<void> setBackgroundId(int id, {bool? forNight}) {
    final n = forNight ?? night;
    if (n) {
      darkbackground = id;
      return _setInt('darkbackground', id);
    }
    background = id;
    return _setInt('background', id);
  }

  Future<void> setNight(bool v) async {
    night = v;
    onNightChanged?.call(v);
    notifyListeners();
  }

  Future<void> setBrightness(double v) {
    brightness = v.clamp(0, 1);
    return _setDouble('brightness', brightness);
  }

  Future<void> setAutoBrightness(bool v) {
    autoBrightness = v;
    return _setBool('autoBrightness', v);
  }

  Future<void> setWakelockTimeout(int v) {
    wakelockTimeout = v;
    return _setInt('wakelockTimeout', v);
  }

  Future<void> setBool(String key, bool v) async {
    switch (key) {
      case 'lock':
        lock = v;
      case 'aichat':
        aichat = v;
      case 'needcss2':
        needcss2 = v;
      case 'bottomfix':
        bottomfix = v;
      case 'downmark':
        downmark = v;
      case 'exit':
        exit = v;
      case 'underline':
        underline = v;
      case 'underlineFullWidth':
        underlineFullWidth = v;
      case 'ispad':
        ispad = v;
      case 'needdp':
        needdp = v;
    }
    await _setBool(key, v);
  }

  Future<void> setInt(String key, int v) async {
    switch (key) {
      case 'readHighlightType':
        readHighlightType = v;
      case 'underlineStyle':
        underlineStyle = v;
      case 'headerFooterFontSize':
        headerFooterFontSize = v.clamp(8, 30);
        v = headerFooterFontSize;
    }
    await _setInt(key, v);
  }

  // ------------------------------------------------------------------ presets ("排版")

  /// The current layout as a `BackGround` (for "新增排版" and the theme editor).
  BackGround toBackGround({int name = 0, String themeName = ''}) {
    final c = config();
    return BackGround(
      name: name,
      themeName: themeName,
      backgroundColor: colorToHex(c.backgroundColor),
      textColor: colorToHex(c.textColor),
      kong: kong,
      lineHeightN: lineHeight,
      letterSpacing: letterSpacing,
      fontWeight: fontWeight,
      topMargin: topMargin,
      bottomMargin: bottomMargin,
      leftMargin: leftMargin,
      rightMargin: rightMargin,
      paragraphSpacing: paragraphSpacing,
      titleTopMargin: titleTopMargin,
      titleBottomMargin: titleBottomMargin,
      titleAlign: titleAlign,
      fen: fen,
      fontSize: fontSize.toDouble(),
      titlefontSize: titlefontSize,
      fontFamily: fontFamily,
      underline: underline,
      underlineStyle: underlineStyle,
      underlineFullWidth: underlineFullWidth,
      topSafeDistance: safeTop,
      bottomSafeDistance: safeBottom,
      headerLeftMargin: headerLeftMargin,
      headerRightMargin: headerRightMargin,
      footerLeftMargin: footerLeftMargin,
      footerRightMargin: footerRightMargin,
      headerFooterFontSize: headerFooterFontSize,
      showTop: showTop,
      showBottom: showBottom,
      ispad: ispad,
    );
  }

  /// "应用排版": copies the layout fields of [b] into the prefs (zero values keep the current setting).
  Future<void> applyLayout(BackGround b) async {
    if (b.fontSize > 0) await Storage.setInt(fontSizeKey, b.fontSize.round().clamp(10, 55));
    if (b.lineHeightN > 0) await Storage.setDouble('lineHeight', b.lineHeightN);
    await Storage.setDouble('letterSpacing', b.letterSpacing);
    if (b.fontWeight > 0) await Storage.setInt('fontWeight12345', b.fontWeight);
    await Storage.setString('fontFamily', b.fontFamily);
    await Storage.setDouble('paragraphSpacing', b.paragraphSpacing);
    await Storage.setInt('kong', b.kong);
    await Storage.setInt('fen', b.fen);
    await Storage.setBool('ispad', b.ispad);
    await Storage.setInt('titleAlign', b.titleAlign);
    await Storage.setInt('titleTopMargin', b.titleTopMargin);
    await Storage.setInt('titleBottomMargin', b.titleBottomMargin);
    await Storage.setInt('titlefontSize', b.titlefontSize);
    await Storage.setInt('topMargin', b.topMargin);
    await Storage.setInt('bottomMargin', b.bottomMargin);
    await Storage.setInt('leftMargin', b.leftMargin);
    await Storage.setInt('rightMargin', b.rightMargin);
    if (b.headerFooterFontSize > 0) await Storage.setInt('headerFooterFontSize', b.headerFooterFontSize);
    await Storage.setBool('showTop', b.showTop);
    await Storage.setBool('showBottom', b.showBottom);
    await Storage.setBool('underline', b.underline);
    reload();
    notifyListeners();
  }

  // ------------------------------------------------------------------ derived values

  int get currentBackgroundId => night ? darkbackground : background;

  /// Font size in logical pixels: the stored value itself. 0x2b3a24 only clamps it to 10..55, the layout (0x236afc: line height =
  /// size * lineHeight) and the text painters (`TextScaler` 1.0) use it unscaled. ([screenShortest] is kept for callers.)
  double fontPx([double screenShortest = 0]) => fontSize.clamp(10, 55).toDouble();

  /// Header / footer text size as the status line paints it (0x6342b8: 0 -> 12, clamped to 8..25).
  double get statusFontSize => (headerFooterFontSize == 0 ? 12 : headerFooterFontSize.clamp(8, 25)).toDouble();

  /// The colours of background id [id] (0x245b64 / 0x245728 / 0xecc920).
  ReadConfig config([int? id]) {
    final i = id ?? currentBackgroundId;
    if (i < builtinColors.length) {
      final bg = parseColor(builtinColors[i]) ?? Colors.white;
      final text = builtinColors[i] == '#000000' ? Colors.white70 : Colors.black87;
      return ReadConfig(backgroundColor: bg, textColor: text);
    }
    if (i < userIdBase) {
      final path = builtinImages[i - imageIdBase];
      return ReadConfig(
        backgroundColor: const Color(0xFFF5EFDF),
        textColor: Colors.black87,
        image: DecorationImage(image: AssetImage(path), fit: BoxFit.cover),
      );
    }
    final g = Ground.byName(i);
    if (g == null) return config(night ? 4 : 0);
    return ReadConfig(
      backgroundColor: parseColor(g.backgroundColor) ?? Colors.white,
      textColor: parseColor(g.textColor) ?? Colors.black87,
      readColor: parseColor(g.readColor),
      menuColor: parseColor(g.menuColor),
      menuTextColor: parseColor(g.menuTextColor),
      image: g.backgroundimage.isEmpty ? null : DecorationImage(image: imageProviderOf(g.backgroundimage), fit: BoxFit.cover),
    );
  }

  static ImageProvider imageProviderOf(String path) {
    if (path.startsWith('lib/assets/')) return AssetImage(path);
    return FileImage(File(path));
  }

  /// Height of the header line / footer line (0 when hidden).
  double get headerHeight => showTop ? statusFontSize + 14.0 : 0;
  double get footerHeight => showBottom ? statusFontSize + 14.0 : 0;

  /// Columns: 界面设置 单列 / 双列 writes `ispad` (0xfa2690).
  int columnsFor(Size size) => ispad ? 2 : 1;

  /// The layout style for a page area of [size] with the system [safe] insets.
  ReadLayoutStyle layoutStyle(Size size, EdgeInsets safe) {
    final fs = fontPx(size.shortestSide);
    final scale = fs / fontSize;
    final top = (safeTop >= 0 ? safeTop.toDouble() : safe.top) + topMargin + headerHeight;
    final bottom = (safeBottom >= 0 ? safeBottom.toDouble() : safe.bottom) + bottomMargin + footerHeight;
    final w = fontWeight.clamp(100, 900);
    return ReadLayoutStyle(
      fontSize: fs,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.values[(w / 100).round().clamp(1, 9) - 1],
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      paragraphSpacing: paragraphSpacing,
      indent: kong,
      titleFontSize: (fontSize + titlefontSize).clamp(8, 80) * scale,
      titleAlign: switch (titleAlign) { 1 => TextAlign.center, 2 => TextAlign.right, _ => TextAlign.left },
      titleTopMargin: titleTopMargin.toDouble(),
      titleBottomMargin: titleBottomMargin.toDouble() + fs,
      padding: EdgeInsets.fromLTRB(leftMargin.toDouble(), top, rightMargin.toDouble(), bottom),
      columns: columnsFor(size),
      // Pages are drawn with Text widgets (selectable); the per-page line stretch of the painter is not used.
      stretchPages: false,
    );
  }

  // ------------------------------------------------------------------ colour helpers

  static Color? parseColor(String s) {
    var t = s.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('#')) t = t.substring(1);
    if (t.startsWith('0x') || t.startsWith('0X')) t = t.substring(2);
    if (t.length == 6) t = 'ff$t';
    if (t.length != 8) return null;
    final v = int.tryParse(t, radix: 16);
    return v == null ? null : Color(v);
  }

  static String colorToHex(Color c) {
    final v = c.toARGB32() & 0xffffff;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }
}
