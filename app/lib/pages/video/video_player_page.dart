// pages/video/video_player_page.dart — the video player (original `_VideoPlayerPageState`, 83 functions; playback through
// cached_video_player_plus in the original, video_player here behind [ReaderVideoController] so tests use a fake). Plays in the app:
// tap shows / hides the controls, a horizontal drag seeks with "快退中..." / "快进中...", progress slider, play / pause, playback speed,
// the position is kept in prefs `video_progress_<id>` (milliseconds; id = the episode url) and restored on the next open.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../storage/storage.dart';
import '../../util/toast.dart';

/// The video engine the page uses.
abstract class ReaderVideoController {
  static ReaderVideoController Function(String url, Map<String, String> headers) create = PluginVideoController.new;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration d);
  Future<void> setSpeed(double s);
  Duration get position;
  Duration get duration;
  bool get isPlaying;
  double get aspectRatio;
  Widget view();
  void addListener(VoidCallback l);
  void removeListener(VoidCallback l);
  Future<void> dispose();
}

class PluginVideoController implements ReaderVideoController {
  final VideoPlayerController _c;
  PluginVideoController(String url, Map<String, String> headers) : _c = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: headers);

  @override
  Future<void> initialize() => _c.initialize();
  @override
  Future<void> play() => _c.play();
  @override
  Future<void> pause() => _c.pause();
  @override
  Future<void> seekTo(Duration d) => _c.seekTo(d);
  @override
  Future<void> setSpeed(double s) => _c.setPlaybackSpeed(s);
  @override
  Duration get position => _c.value.position;
  @override
  Duration get duration => _c.value.duration;
  @override
  bool get isPlaying => _c.value.isPlaying;
  @override
  double get aspectRatio => _c.value.aspectRatio <= 0 ? 16 / 9 : _c.value.aspectRatio;
  @override
  Widget view() => VideoPlayer(_c);
  @override
  void addListener(VoidCallback l) => _c.addListener(l);
  @override
  void removeListener(VoidCallback l) => _c.removeListener(l);
  @override
  Future<void> dispose() => _c.dispose();
}

class VideoPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final Map<String, String> headers;

  /// Called when the episode finished (the video view opens the next one).
  final VoidCallback? onCompleted;

  const VideoPlayerPage({super.key, required this.url, this.title = '', this.headers = const {}, this.onCompleted});

  static String progressKey(String id) => 'video_progress_$id';

  @override
  State<VideoPlayerPage> createState() => VideoPlayerPageState();
}

class VideoPlayerPageState extends State<VideoPlayerPage> {
  ReaderVideoController? _c;
  String? _error;
  bool _ready = false;
  bool _controls = true;
  double _speed = 1;
  double? _dragSeconds;
  double _dragDx = 0;
  bool _completed = false;
  Timer? _hide;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  ReaderVideoController? get controller => _c;
  bool get valid {
    final u = Uri.tryParse(widget.url);
    return u != null && u.hasScheme && u.host.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (valid) _open();
  }

  Future<void> _open() async {
    final c = ReaderVideoController.create(widget.url, widget.headers);
    _c = c;
    try {
      await c.initialize();
      final saved = Storage.getInt(VideoPlayerPage.progressKey(widget.url));
      if (saved > 0 && saved < c.duration.inMilliseconds - 3000) await c.seekTo(Duration(milliseconds: saved));
      c.addListener(_tick);
      await c.play();
      if (!mounted) return;
      setState(() => _ready = true);
      _autoHide();
    } catch (e) {
      if (mounted) setState(() => _error = '获取失败: $e');
    }
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) _save();
    final ended = c.duration > Duration.zero && c.position >= c.duration && !c.isPlaying;
    if (ended && !_completed) {
      _completed = true;
      Storage.setInt(VideoPlayerPage.progressKey(widget.url), 0);
      widget.onCompleted?.call();
    }
    setState(() {});
  }

  Future<void> _save() async {
    final c = _c;
    if (c == null || !_ready) return;
    _lastSave = DateTime.now();
    await Storage.setInt(VideoPlayerPage.progressKey(widget.url), c.position.inMilliseconds);
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && (_c?.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _save();
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    final c = _c;
    if (c == null) return;
    c.isPlaying ? await c.pause() : await c.play();
    _autoHide();
    if (mounted) setState(() {});
  }

  Future<void> setSpeed(double s) async {
    _speed = s;
    await _c?.setSpeed(s);
    if (mounted) setState(() {});
  }

  static String fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // horizontal drag = seek, 1 px = 0.2 s
  void _dragStart(DragStartDetails d) {
    if (!_ready) return;
    _dragDx = 0;
    _dragSeconds = _c!.position.inMilliseconds / 1000;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_dragSeconds == null) return;
    _dragDx += d.delta.dx;
    setState(() {});
  }

  Future<void> _dragEnd(DragEndDetails d) async {
    final start = _dragSeconds;
    if (start == null) return;
    final c = _c!;
    final to = (start + _dragDx * 0.2).clamp(0, c.duration.inMilliseconds / 1000);
    setState(() => _dragSeconds = null);
    await c.seekTo(Duration(milliseconds: (to * 1000).round()));
  }

  Widget _player() {
    final c = _c!;
    final pos = c.position, dur = c.duration;
    final drag = _dragSeconds;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: () {
        setState(() => _controls = !_controls);
        if (_controls) _autoHide();
      },
      onDoubleTap: toggle,
      onHorizontalDragStart: _dragStart,
      onHorizontalDragUpdate: _dragUpdate,
      onHorizontalDragEnd: _dragEnd,
      child: Stack(fit: StackFit.expand, children: [
        Center(child: AspectRatio(aspectRatio: c.aspectRatio, child: c.view())),
        if (drag != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(
                '${_dragDx < 0 ? '快退中...' : '快进中...'}\n'
                '${fmt(Duration(milliseconds: ((drag + _dragDx * 0.2).clamp(0, dur.inMilliseconds / 1000) * 1000).round()))} / ${fmt(dur)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        if (_controls)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black45,
              child: SafeArea(
                top: false,
                child: Row(children: [
                  IconButton(
                    key: const ValueKey('video_play'),
                    color: Colors.white,
                    icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: toggle,
                  ),
                  Text(fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: dur.inMilliseconds <= 0 ? 0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                      max: dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds.toDouble(),
                      onChanged: dur.inMilliseconds <= 0 ? null : (v) => c.seekTo(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text(fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    initialValue: _speed,
                    onSelected: setSpeed,
                    itemBuilder: (_) => [for (final s in speeds) PopupMenuItem(value: s, child: Text('${s}x'))],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!valid) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('无效的视频地址 ：${widget.url}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.url));
                Toast.show('地址已复制');
              },
              child: const Text('复制地址'),
            ),
          ]),
        ),
      );
    } else if (_error != null) {
      body = Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)));
    } else if (!_ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _player();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: body,
    );
  }
}
