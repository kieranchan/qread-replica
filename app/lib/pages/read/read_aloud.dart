// pages/read/read_aloud.dart — reads a book paragraph by paragraph through a [ReaderSpeaker] and tells the reader which range is being
// spoken, so it can highlight it and follow the pages; chapter changes, speed and the stop timer ("定时停止") live here too.
//
// Original: `_NovelViewState` + `TtsController` (`_TtsSeg` segments of the chapter, timer prefs `autoListenTimer` / `listenTimerMinutes`,
// speed `readspeed2`). The multi-role engine ("多角色引擎需要ai支持，请先配置ai接口") belongs to the TTS area.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../read/api/readapi.dart';
import '../../read/util/read.dart';
import '../../storage/storage.dart';
import 'reader_speaker.dart';

/// One spoken paragraph: chapter-text range `[start, end)`; the title has `start == -1`.
class AloudSegment {
  final String text;
  final int start;
  final int end;
  const AloudSegment(this.text, this.start, this.end);
}

/// Follows the state of listening: lock-screen controls, background music (registered by `TtsBridge.install()`).
abstract class ListenObserver {
  void listenChanged(ReadAloudController c);
}

class ReadAloudController extends ChangeNotifier {
  /// Notified on every change of any controller.
  static final List<ListenObserver> observers = [];

  final ReaderSpeaker speaker;

  /// Book name and cover for the lock screen.
  String bookName = '';
  String coverUrl = '';

  @override
  void notifyListeners() {
    // 0x1e04: while audio plays the screen-awake timer keeps renewing the activity
    ReaderWakelock.keepAwake = active && !paused;
    super.notifyListeners();
    for (final o in List<ListenObserver>.of(observers)) {
      try {
        o.listenChanged(this);
      } catch (_) {}
    }
  }

  /// Loads chapter [index] (null when it does not exist).
  final Future<ReadChapter?> Function(int index) chapterAt;
  final int Function() chapterCount;

  /// Called whenever a new segment starts (the reader turns to the page that shows it).
  void Function(int chapterIndex, AloudSegment segment)? onSegment;

  /// Called when reading ends (end of the book, timer, stop).
  VoidCallback? onStopped;

  ReadAloudController({required this.speaker, required this.chapterAt, required this.chapterCount}) {
    speaker.onDone = _next;
    speaker.onError = (m) {
      error = m;
      stop();
    };
    rate = Storage.getDouble('readspeed2', 1).clamp(0.2, 3.0);
    if (rate == 0) rate = 1;
  }

  int chapterIndex = 0;
  List<AloudSegment> segments = const [];
  int segmentIndex = 0;
  bool active = false;
  bool paused = false;
  double rate = 1;
  String? error;
  String chapterTitle = '';

  /// When the timer stops reading (null = no timer).
  DateTime? stopAt;
  Timer? _timer;
  int _generation = 0;

  AloudSegment? get current => active && segmentIndex < segments.length ? segments[segmentIndex] : null;

  static List<AloudSegment> segmentsOf(ReadChapter rc, {bool withTitle = true}) {
    final out = <AloudSegment>[];
    if (withTitle && rc.title.trim().isNotEmpty) out.add(AloudSegment(rc.title.trim(), -1, -1));
    for (final b in rc.content.blocks) {
      if (b.isImage) continue;
      final runs = b.runs.where((r) => r.str.isNotEmpty).toList();
      if (runs.isEmpty) continue;
      final text = runs.map((r) => r.str).join().trim();
      if (text.isEmpty) continue;
      out.add(AloudSegment(text, runs.first.start, runs.last.end));
    }
    return out;
  }

  /// Starts reading chapter [index] at the paragraph that contains (or follows) chapter offset [fromOffset].
  Future<void> start(int index, {int fromOffset = 0, bool withTitle = true}) async {
    final gen = ++_generation;
    error = null;
    final rc = await chapterAt(index);
    if (gen != _generation) return;
    if (rc == null) {
      await stop();
      return;
    }
    chapterIndex = index;
    chapterTitle = rc.title;
    segments = segmentsOf(rc, withTitle: withTitle && fromOffset <= 0);
    segmentIndex = 0;
    if (fromOffset > 0) {
      final i = segments.indexWhere((s) => s.end > fromOffset);
      segmentIndex = i < 0 ? segments.length : i;
    }
    active = true;
    paused = false;
    await speaker.setRate(rate);
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (!active) return;
    if (segmentIndex >= segments.length) {
      await _nextChapter();
      return;
    }
    final s = segments[segmentIndex];
    onSegment?.call(chapterIndex, s);
    notifyListeners();
    await speaker.speak(s.text);
  }

  void _next() {
    if (!active || paused) return;
    if (stopAt != null && DateTime.now().isAfter(stopAt!)) {
      stop();
      return;
    }
    segmentIndex++;
    _speakCurrent();
  }

  Future<void> _nextChapter() async {
    if (chapterIndex + 1 >= chapterCount()) {
      await stop();
      return;
    }
    await start(chapterIndex + 1);
  }

  Future<void> nextSegment() async {
    if (!active) return;
    await speaker.stop();
    segmentIndex++;
    paused = false;
    await _speakCurrent();
  }

  Future<void> prevSegment() async {
    if (!active) return;
    await speaker.stop();
    segmentIndex = (segmentIndex - 1).clamp(0, segments.isEmpty ? 0 : segments.length - 1);
    paused = false;
    await _speakCurrent();
  }

  Future<void> pause() async {
    if (!active || paused) return;
    paused = true;
    await speaker.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    if (!active || !paused) return;
    paused = false;
    notifyListeners();
    await speaker.resume();
  }

  Future<void> stop() async {
    _generation++;
    final was = active;
    active = false;
    paused = false;
    _cancelTimer();
    try {
      await speaker.stop();
    } catch (_) {}
    notifyListeners();
    if (was) onStopped?.call();
  }

  Future<void> setRate(double v) async {
    rate = double.parse(v.clamp(0.2, 3.0).toStringAsFixed(1));
    await Storage.setDouble('readspeed2', rate);
    await speaker.setRate(rate);
    notifyListeners();
  }

  /// "定时停止": stops after [minutes] (0 = cancel). Persisted as `listenTimerMinutes` like the original.
  void setTimer(int minutes) {
    _cancelTimer();
    if (minutes <= 0) {
      notifyListeners();
      return;
    }
    stopAt = DateTime.now().add(Duration(minutes: minutes));
    Storage.setString('listenTimerMinutes', '$minutes');
    _timer = Timer(Duration(minutes: minutes), () => stop());
    notifyListeners();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    stopAt = null;
  }

  Duration? get timerLeft {
    final s = stopAt;
    if (s == null) return null;
    final d = s.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void dispose() {
    _generation++;
    _cancelTimer();
    if (active) {
      active = false;
      paused = false;
      notifyListeners();
    }
    speaker.onDone = null;
    speaker.onError = null;
    speaker.stop();
    super.dispose();
  }
}
