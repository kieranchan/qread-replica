// dev/qa_driver.dart — remote taps for checking the app on the owner's phone over USB (not part of the original).
//
// Off unless the file `<documents>/.qa_driver` exists. That file can only be written by the app itself or, for this sideloaded
// development build, by the paired computer (`pymobiledevice3 apps push`); its first line is a token every request must carry
// (`k=<token>`). When on, a small HTTP server listens on 127.0.0.1:8765 only; the computer reaches it through usbmux
// (`phone/phone.py` at the repository root, see app/README.md). Requests (GET, coordinates in logical pixels):
//   /size                       screen size and pixel ratio
//   /texts                      visible texts with their rectangles (`hit` = a tap at the centre reaches that text)
//   /sem                        semantics labels with rectangles and actions (buttons, icons with tooltips)
//   /tap?x=&y=                  a tap
//   /long?x=&y=&ms=             a long press
//   /drag?x1=&y1=&x2=&y2=&ms=   a drag
//   /type?s=                    replaces the text of the focused field;  /submit  runs its keyboard action
//   /back                       pops the topmost route that can be popped
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../common/app_dirs.dart';
import '../pages/read/pages/novel/apple_book.dart';

abstract class QaDriver {
  static const int port = 8765;
  static HttpServer? _server;
  static SemanticsHandle? _semantics;
  static int _pointer = 9000;

  /// True while the server listens.
  static bool get running => _server != null;

  static Future<void> start() async {
    if (_server != null || !AppDirs.hasRoot) return;
    final flag = File('${AppDirs.root.path}/.qa_driver');
    if (!flag.existsSync()) return;
    final token = flag.readAsLinesSync().firstOrNull?.trim() ?? '';
    if (token.length < 16) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (_) {
      return;
    }
    _server!.listen((req) => _handle(req, token));
  }

  static Future<void> _handle(HttpRequest req, String token) async {
    final q = req.uri.queryParameters;
    Object? out;
    var status = 200;
    try {
      if (q['k'] != token) {
        status = 403;
        out = 'bad token';
      } else {
        out = await run(req.uri.path, q);
      }
    } catch (e) {
      status = 500;
      out = '$e';
    }
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(jsonEncode(out));
    await req.response.close();
  }

  static double _d(Map<String, String> q, String k, [double def = 0]) => double.tryParse(q[k] ?? '') ?? def;

  @visibleForTesting
  static Future<Object?> run(String path, Map<String, String> q) async {
    switch (path) {
      case '/size':
        final v = WidgetsBinding.instance.platformDispatcher.implicitView!;
        return {'w': v.physicalSize.width / v.devicePixelRatio, 'h': v.physicalSize.height / v.devicePixelRatio, 'dpr': v.devicePixelRatio};
      case '/texts':
        return _texts();
      case '/sem':
        _semantics ??= SemanticsBinding.instance.ensureSemantics();
        await SchedulerBinding.instance.endOfFrame;
        return _sem();
      case '/tap':
        final at = Offset(_d(q, 'x'), _d(q, 'y'));
        // a tap on the native page view of 仿真翻页(IOS原生): pointer events cannot reach it, the pager takes the tap itself
        final hit = HitTestResult();
        GestureBinding.instance.hitTestInView(hit, at, _view);
        final hook = AppleBookPager.qaTapHook;
        if (hook != null && hit.path.any((e) => e.target is RenderUiKitView)) {
          hook(at);
          return 'native';
        }
        await _tap(at, const Duration(milliseconds: 60));
        return 'ok';
      case '/long':
        await _tap(Offset(_d(q, 'x'), _d(q, 'y')), Duration(milliseconds: _d(q, 'ms', 700).round()));
        return 'ok';
      case '/drag':
        await _drag(Offset(_d(q, 'x1'), _d(q, 'y1')), Offset(_d(q, 'x2'), _d(q, 'y2')), Duration(milliseconds: _d(q, 'ms', 300).round()));
        return 'ok';
      case '/type':
        final st = _field();
        if (st == null) return 'no focused field';
        final s = q['s'] ?? '';
        st.userUpdateTextEditingValue(
            TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length)), SelectionChangedCause.keyboard);
        return 'ok';
      case '/submit':
        final st = _field();
        if (st == null) return 'no focused field';
        st.performAction(st.widget.textInputAction ?? TextInputAction.done);
        return 'ok';
      case '/back':
        final navs = <NavigatorState>[];
        void visit(Element e) {
          if (e is StatefulElement && e.state is NavigatorState) navs.add(e.state as NavigatorState);
          e.visitChildren(visit);
        }
        final root = WidgetsBinding.instance.rootElement;
        if (root != null) visit(root);
        for (final n in navs.reversed) {
          if (n.canPop()) {
            await n.maybePop();
            return 'popped';
          }
        }
        return 'nothing to pop';
    }
    return 'unknown $path';
  }

  static EditableTextState? _field() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    if (ctx is StatefulElement && ctx.state is EditableTextState) return ctx.state as EditableTextState;
    return ctx.findAncestorStateOfType<EditableTextState>();
  }

  static int get _view => WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;

  static void _send(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);

  static Future<void> _tap(Offset at, Duration hold) async {
    final p = ++_pointer;
    _send(PointerDownEvent(pointer: p, position: at, viewId: _view, timeStamp: _now()));
    await Future<void>.delayed(hold);
    _send(PointerUpEvent(pointer: p, position: at, viewId: _view, timeStamp: _now()));
  }

  static Future<void> _drag(Offset from, Offset to, Duration time) async {
    final p = ++_pointer;
    const steps = 20;
    _send(PointerDownEvent(pointer: p, position: from, viewId: _view, timeStamp: _now()));
    var last = from;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(time ~/ steps);
      final at = Offset.lerp(from, to, i / steps)!;
      _send(PointerMoveEvent(pointer: p, position: at, delta: at - last, viewId: _view, timeStamp: _now()));
      last = at;
    }
    _send(PointerUpEvent(pointer: p, position: to, viewId: _view, timeStamp: _now()));
  }

  static final Stopwatch _clock = Stopwatch()..start();
  static Duration _now() => _clock.elapsed;

  static Rect _globalRect(RenderBox b) => MatrixUtils.transformRect(b.getTransformTo(null), Offset.zero & b.size);

  /// Walks stop after this long / this many entries, so a page with a platform view (浏览器, 书源登录) answers a partial list
  /// instead of leaving the driver unanswered (seen on the phone: `/texts` never returned on a WebView page).
  static const Duration walkBudget = Duration(seconds: 3);
  static const int walkLimit = 400;

  static List<Map<String, Object?>> _texts() {
    final out = <Map<String, Object?>>[];
    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final sw = Stopwatch()..start();
    void visit(Element e) {
      if (sw.elapsed > walkBudget || out.length >= walkLimit) return;
      final ro = e.renderObject;
      if (e is RenderObjectElement && ro is RenderParagraph && ro.attached && ro.hasSize) {
        final r = _globalRect(ro);
        final text = ro.text.toPlainText().trim();
        if (text.isNotEmpty && r.overlaps(screen)) {
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, r.center, _view);
          out.add({
            't': text.length > 80 ? '${text.substring(0, 80)}…' : text,
            'r': [r.left.round(), r.top.round(), r.right.round(), r.bottom.round()],
            'hit': hit.path.any((h) => h.target == ro),
          });
        }
      }
      e.visitChildren(visit);
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return out;
  }

  static List<Map<String, Object?>> _sem() {
    final out = <Map<String, Object?>>[];
    final view = WidgetsBinding.instance.renderViews.first;
    final dpr = WidgetsBinding.instance.platformDispatcher.implicitView!.devicePixelRatio;
    final rootNode = view.owner?.semanticsOwner?.rootSemanticsNode;
    final sw = Stopwatch()..start();
    void visit(SemanticsNode n, Matrix4 parent) {
      if (sw.elapsed > walkBudget || out.length >= walkLimit) return;
      final m = n.transform == null ? parent : (parent.clone()..multiply(n.transform!));
      final r = MatrixUtils.transformRect(m, n.rect);
      final d = n.getSemanticsData();
      final label = [d.label, d.value, d.tooltip, d.hint].where((s) => s.isNotEmpty).join(' | ');
      if (label.isNotEmpty || d.hasAction(SemanticsAction.tap)) {
        out.add({
          'l': label.length > 80 ? '${label.substring(0, 80)}…' : label,
          'r': [r.left / dpr, r.top / dpr, r.right / dpr, r.bottom / dpr].map((v) => v.round()).toList(),
          if (d.hasAction(SemanticsAction.tap)) 'tap': true,
        });
      }
      n.visitChildren((c) {
        visit(c, m);
        return true;
      });
    }
    if (rootNode != null) visit(rootNode, Matrix4.identity());
    return out;
  }
}
