// pages/read/pages/audio_view.dart — the audio-book player (original `_AudioViewState`, 92 functions; key `audio_<bookUrl>`). The text
// of a chapter of an audio source is the audio URL. Strings: 目录 · 刷新 · 更多 · 加入书架 · 定时 · 字幕 · 语速 / 播放速度 · 片头片尾 ·
// 片头片尾设置 · 片头跳过时间 · 片尾跳过时间 · 输入跳过秒数 · 请输入有效的时间 · 取消定时 · 当前已设置定时，是否确认要取消定时？ · 定时停止 ·
// 分钟 · 刷新章节失败: . Per-book prefs `skipStartTime<bookUrl>` / `skipEndTime<bookUrl>` (seconds), timer `audioTimerMinutes`.
// Playback goes through [ReaderAudioPlayer] (default: just_audio) so tests can use a fake.
// 字幕: the source's content rule hands the lyric over with the JS bridge's `putLyric` (or the 正文副本 rule, "┌获取副文歌词"); the
// original keeps it in its cache under `book_<bookUrl>_<index>_chapter_lyric` (0xe8e9f0 writes, 0xf98118 reads) and the audio view shows
// it. [AudioLyrics.read] reads that key from the item store (the engine's `putLyric` must write it there); LRC lines after the audio URL
// in the chapter text are used as well.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../common/nav.dart';
import '../../../models/book.dart';
import '../../../models/bookchapter.dart';
import '../../../read/api/readapi.dart';
import '../../../storage/storage.dart';
import '../../../util/toast.dart';
import '../tts_bridge.dart';
import 'lyrics_view.dart';
import 'novel_view.dart' show ChapterListLoader;

/// The audio engine the view uses.
abstract class ReaderAudioPlayer {
  static ReaderAudioPlayer Function()? factory;
  static ReaderAudioPlayer create() => factory?.call() ?? JustAudioReaderPlayer();

  Future<Duration?> setUrl(String url, {Map<String, String>? headers});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();

  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;

  /// Fires when the current item finished.
  Stream<void> get completedStream;
  Duration? get duration;
  bool get playing;
}

class JustAudioReaderPlayer implements ReaderAudioPlayer {
  final AudioPlayer _p = AudioPlayer();

  @override
  Future<Duration?> setUrl(String url, {Map<String, String>? headers}) => _p.setUrl(url, headers: headers);
  @override
  Future<void> play() => _p.play();
  @override
  Future<void> pause() => _p.pause();
  @override
  Future<void> seek(Duration position) => _p.seek(position);
  @override
  Future<void> setSpeed(double speed) => _p.setSpeed(speed);
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> dispose() => _p.dispose();
  @override
  Stream<Duration> get positionStream => _p.positionStream;
  @override
  Stream<bool> get playingStream => _p.playingStream;
  @override
  Stream<void> get completedStream => _p.processingStateStream.where((s) => s == ProcessingState.completed);
  @override
  Duration? get duration => _p.duration;
  @override
  bool get playing => _p.playing;
}

/// The chapter lyric store shared with the engine's `putLyric`.
abstract class AudioLyrics {
  static String key(String bookUrl, int index) => 'book_${bookUrl}_${index}_chapter_lyric';

  static Future<String> Function(String bookUrl, int index) read = (bookUrl, index) async {
    try {
      return await Storage.read(key(bookUrl, index));
    } catch (_) {
      return '';
    }
  };

  static Future<void> write(String bookUrl, int index, String lrc) => Storage.write(key(bookUrl, index), lrc);
}

class AudioView extends StatefulWidget {
  final Book book;
  final List<BookChapter>? chapters;
  final int? chapterIndex;
  final ChapterLoader? loader;
  final ChapterListLoader? chapterListLoader;

  const AudioView({super.key, required this.book, this.chapters, this.chapterIndex, this.loader, this.chapterListLoader});

  @override
  State<AudioView> createState() => AudioViewState();
}

class AudioViewState extends State<AudioView> {
  final ReaderAudioPlayer _player = ReaderAudioPlayer.create();
  late ReadApi _api;
  List<BookChapter> _chapters = [];
  int _ci = 0;
  Duration _pos = Duration.zero;
  bool _playing = false;
  double _speed = 1;
  String _lyrics = '';
  bool _showLyrics = false;
  String? _error;
  Timer? _timer;
  DateTime? _stopAt;
  final List<StreamSubscription<Object?>> _subs = [];
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  int get chapterIndex => _ci;
  String get _skipStartKey => 'skipStartTime${widget.book.bookUrl}';
  String get _skipEndKey => 'skipEndTime${widget.book.bookUrl}';

  @override
  void initState() {
    super.initState();
    _speed = Storage.getDouble('readspeed', 1).clamp(0.5, 3.0);
    _subs.add(_player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      _checkSkipEnd(p);
      if (DateTime.now().difference(_lastSave).inSeconds >= 5) _save();
    }));
    _subs.add(_player.playingStream.listen((v) {
      if (mounted) setState(() => _playing = v);
      _media(v);
    }));
    _subs.add(_player.completedStream.listen((_) => _next()));
    _init();
  }

  /// Lock-screen / Control Center state of the audio book (the session of tts_bridge.dart, when installed).
  void _media(bool playing) {
    final m = ListenMediaSession.backend;
    if (m == null) return;
    m.onCommand = (cmd) {
      if (!mounted) return;
      switch (cmd) {
        case 'play':
          _player.play();
        case 'pause':
        case 'stop':
          _player.pause();
        case 'next':
          if (_ci + 1 < _chapters.length) _open(_ci + 1);
        case 'previous':
          if (_ci > 0) _open(_ci - 1);
      }
    };
    final title = _ci < _chapters.length ? _chapters[_ci].name : '';
    m.update(title: title, album: widget.book.name, artUri: widget.book.coverUrl, playing: playing, active: true).catchError((_) {});
  }

  @override
  void dispose() {
    final m = ListenMediaSession.backend;
    if (m != null) m.update(title: '', album: widget.book.name, artUri: '', playing: false, active: false).catchError((_) {});
    _save();
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      var list = widget.chapters;
      if (list == null || list.isEmpty) list = await widget.chapterListLoader?.call(widget.book) ?? const [];
      _chapters = List.of(list);
      if (_chapters.isEmpty) {
        setState(() => _error = '章节列表为空');
        return;
      }
      _api = ReadApi(widget.book, chapters: _chapters, loader: widget.loader);
      var start = widget.chapterIndex ?? widget.book.durChapterIndex;
      if (start < 0 || start >= _chapters.length) start = 0;
      await _open(start, resume: widget.chapterIndex == null);
    } catch (e) {
      if (mounted) setState(() => _error = '初始化失败: $e');
    }
  }

  Future<void> _open(int i, {bool resume = false}) async {
    setState(() {
      _ci = i;
      _error = null;
    });
    try {
      final rc = await _api.loadChapter(i);
      final lines = rc.content.text.trim().split('\n');
      final url = lines.first.trim();
      _lyrics = lines.skip(1).join('\n');
      if (_lyrics.trim().isEmpty) _lyrics = await AudioLyrics.read(widget.book.bookUrl, i);
      final d = await _player.setUrl(url);
      await _player.setSpeed(_speed);
      final skip = Duration(seconds: Storage.getInt(_skipStartKey));
      Duration start = skip;
      if (resume && d != null && widget.book.durChapterPos > 0) {
        start = d * widget.book.durChapterPos;
      }
      if (start > Duration.zero) await _player.seek(start);
      await _player.play();
      await _save();
    } catch (e) {
      Toast.show('刷新章节失败: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _checkSkipEnd(Duration p) {
    final end = Storage.getInt(_skipEndKey);
    final d = _player.duration;
    if (end <= 0 || d == null) return;
    if (p >= d - Duration(seconds: end)) _next();
  }

  bool _advancing = false;
  Future<void> _next() async {
    if (_advancing) return;
    _advancing = true;
    try {
      if (_stopAt != null && DateTime.now().isAfter(_stopAt!)) {
        await _player.pause();
        return;
      }
      if (_ci + 1 < _chapters.length) {
        await _open(_ci + 1);
      } else {
        await _player.pause();
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> _save() async {
    if (_chapters.isEmpty) return;
    _lastSave = DateTime.now();
    final d = _player.duration;
    final pos = d == null || d.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / d.inMilliseconds;
    try {
      await _api.saveProgress(chapterIndex: _ci, pos: pos);
    } catch (_) {}
  }

  Future<void> _setTimer() async {
    if (_stopAt != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('取消定时'),
          content: const Text('当前已设置定时，是否确认要取消定时？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (ok == true) {
        _timer?.cancel();
        setState(() => _stopAt = null);
      }
      return;
    }
    if (!mounted) return;
    final m = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('定时停止')),
          for (final m in const [15, 30, 60, 90]) ListTile(title: Text('$m 分钟'), onTap: () => Navigator.pop(ctx, m)),
        ]),
      ),
    );
    if (m == null) return;
    await Storage.setString('audioTimerMinutes', '$m');
    _timer?.cancel();
    _timer = Timer(Duration(minutes: m), () => _player.pause());
    setState(() => _stopAt = DateTime.now().add(Duration(minutes: m)));
  }

  Future<void> _skipSetting() async {
    final start = TextEditingController(text: '${Storage.getInt(_skipStartKey)}');
    final end = TextEditingController(text: '${Storage.getInt(_skipEndKey)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('片头片尾设置'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: start, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '片头跳过时间', hintText: '输入跳过秒数')),
          TextField(controller: end, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '片尾跳过时间', hintText: '输入跳过秒数')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    final s = int.tryParse(start.text.trim());
    final e = int.tryParse(end.text.trim());
    if (ok != true) return;
    if (s == null || e == null || s < 0 || e < 0) {
      Toast.show('请输入有效的时间');
      return;
    }
    await Storage.setInt(_skipStartKey, s);
    await Storage.setInt(_skipEndKey, e);
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = _player.duration ?? Duration.zero;
    final title = _chapters.isEmpty ? '' : _chapters[_ci].name;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.name),
        actions: [
          IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _chapters.isEmpty ? null : () => _open(_ci)),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) => switch (v) {
              'skip' => _skipSetting(),
              'detail' => Nav.openBook(context, widget.book),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'skip', child: Text('片头片尾')),
              PopupMenuItem(value: 'detail', child: Text('加入书架')),
            ],
          ),
        ],
      ),
      body: _error != null && _chapters.isEmpty
          ? Center(child: Text(_error!))
          : Column(children: [
              ListTile(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: _showLyrics && _lyrics.isNotEmpty
                    ? LyricsView(lrc: _lyrics, position: _pos)
                    : Center(child: Icon(Icons.album, size: 160, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4))),
              ),
              Slider(
                value: d.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0),
                onChanged: d.inMilliseconds == 0 ? null : (v) => _player.seek(d * v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [Text(_fmt(_pos)), const Spacer(), Text(_fmt(d))]),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(icon: const Icon(Icons.skip_previous), onPressed: _ci > 0 ? () => _open(_ci - 1) : null),
                IconButton(iconSize: 56, icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle), onPressed: _playing ? _player.pause : _player.play),
                IconButton(icon: const Icon(Icons.skip_next), onPressed: _ci + 1 < _chapters.length ? () => _open(_ci + 1) : null),
              ]),
              SafeArea(
                top: false,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (ctx) => ListView.builder(
                        itemCount: _chapters.length,
                        itemBuilder: (_, i) => ListTile(
                          selected: i == _ci,
                          title: Text(_chapters[i].name),
                          onTap: () {
                            Navigator.pop(ctx);
                            _open(i);
                          },
                        ),
                      ),
                    ),
                    child: const Text('目录'),
                  ),
                  TextButton(onPressed: _setTimer, child: Text(_stopAt == null ? '定时' : '取消定时')),
                  TextButton(onPressed: () => setState(() => _showLyrics = !_showLyrics), child: const Text('字幕')),
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    onSelected: (v) async {
                      setState(() => _speed = v);
                      await Storage.setDouble('readspeed', v);
                      await _player.setSpeed(v);
                    },
                    itemBuilder: (_) => [for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0, 3.0]) PopupMenuItem(value: v, child: Text('${v}x'))],
                    child: Padding(padding: const EdgeInsets.all(12), child: Text('语速 ${_speed}x')),
                  ),
                ]),
              ),
            ]),
    );
  }
}
