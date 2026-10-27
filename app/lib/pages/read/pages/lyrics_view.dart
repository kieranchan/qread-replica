// pages/read/pages/lyrics_view.dart — subtitles of an audio chapter (original `_LyricsViewState`): LRC lines (`[mm:ss.xx]text`) with the
// line at the current playback position highlighted and kept in view; text without time tags is shown as is.
import 'package:flutter/material.dart';

class LrcLine {
  final Duration time;
  final String text;
  const LrcLine(this.time, this.text);
}

final RegExp _tag = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text; lines without a time tag get the time of the previous line.
List<LrcLine> parseLrc(String lrc) {
  final out = <LrcLine>[];
  var last = Duration.zero;
  for (final raw in lrc.split('\n')) {
    final tags = _tag.allMatches(raw).toList();
    final text = raw.replaceAll(_tag, '').trim();
    if (tags.isEmpty) {
      if (text.isNotEmpty) out.add(LrcLine(last, text));
      continue;
    }
    for (final m in tags) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      last = Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms);
      out.add(LrcLine(last, text));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Index of the line shown at [position] (-1 before the first).
int lrcIndexAt(List<LrcLine> lines, Duration position) {
  var i = -1;
  for (var k = 0; k < lines.length; k++) {
    if (lines[k].time <= position) {
      i = k;
    } else {
      break;
    }
  }
  return i;
}

class LyricsView extends StatefulWidget {
  final String lrc;
  final Duration position;
  const LyricsView({super.key, required this.lrc, required this.position});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late List<LrcLine> _lines = parseLrc(widget.lrc);
  final ScrollController _scroll = ScrollController();
  int _cur = -1;

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.lrc != widget.lrc) _lines = parseLrc(widget.lrc);
    final i = lrcIndexAt(_lines, widget.position);
    if (i != _cur) {
      _cur = i;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && i >= 0) {
          _scroll.animateTo((i * 36.0 - 120).clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView.builder(
      controller: _scroll,
      itemExtent: 36,
      itemCount: _lines.length,
      itemBuilder: (_, i) => Center(
        child: Text(
          _lines[i].text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: i == _cur ? primary : null, fontWeight: i == _cur ? FontWeight.bold : null),
        ),
      ),
    );
  }
}
