// pages/read/listen_page.dart — the full-screen "听书" page (original `_ListenPageState` + `_TtsLyricsViewState`: the chapter as a lyrics
// view with the spoken paragraph highlighted, controls, 语速, 定时停止 / 取消定时, 发音人, 朗读引擎：, the voice download hint, background
// music). It drives the same [ReadAloudController] as the reader's listen bar.
// TODO(asm 0xf677b4): background music (选择背景音乐 / 背景音乐音量) and the multi-role engine belong to the TTS area and are not wired here.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'pages/novel/views/listen_bar.dart';
import 'read_aloud.dart';
import 'reader_speaker.dart';

class ListenPage extends StatefulWidget {
  final ReadAloudController controller;
  final String bookName;
  final String coverUrl;

  const ListenPage({super.key, required this.controller, required this.bookName, this.coverUrl = ''});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> {
  ReadAloudController get c => widget.controller;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _voices() async {
    final list = await c.speaker.voices();
    if (!mounted) return;
    final hint = Platform.isIOS
        ? '前往 设置 → 辅助功能 → 阅读与朗读 → 语音 下载更多发音人'
        : '前往 系统设置 → 辅助功能 → 阅读与朗读 → 系统语音 下载更多发音人';
    final v = await showModalBottomSheet<SpeakerVoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('发音人')),
            ListTile(title: const Text('系统默认'), onTap: () => Navigator.pop(ctx)),
            for (final v in list) ListTile(title: Text(v.name), subtitle: Text(v.locale), onTap: () => Navigator.pop(ctx, v)),
            Padding(padding: const EdgeInsets.all(16), child: Text(hint, style: Theme.of(ctx).textTheme.bodySmall)),
          ],
        ),
      ),
    );
    if (v != null) await c.speaker.setVoice(v);
  }

  @override
  Widget build(BuildContext context) {
    final segs = c.segments;
    final cur = c.segmentIndex;
    final left = c.timerLeft;
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName),
        actions: [IconButton(tooltip: '发音人', icon: const Icon(Icons.record_voice_over), onPressed: _voices)],
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(c.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('朗读引擎：${c.speaker.engineName}'),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              itemCount: segs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  segs[i].text,
                  style: TextStyle(
                    fontSize: i == cur ? 18 : 16,
                    color: i == cur ? primary : null,
                    fontWeight: i == cur ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
          Row(children: [
            const SizedBox(width: 16),
            const Text('语速'),
            Expanded(
              child: Slider(value: c.rate.clamp(0.2, 3.0), min: 0.2, max: 3.0, divisions: 28, label: c.rate.toStringAsFixed(1), onChanged: c.setRate),
            ),
            Text('${c.rate.toStringAsFixed(1)}x'),
            const SizedBox(width: 16),
          ]),
          SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(left == null ? '定时停止' : formatLeft(left)),
                  onPressed: () => showListenTimer(context, c),
                ),
                IconButton(iconSize: 32, icon: const Icon(Icons.skip_previous), onPressed: c.prevSegment),
                IconButton(
                  iconSize: 48,
                  icon: Icon(!c.active || c.paused ? Icons.play_circle : Icons.pause_circle),
                  onPressed: () {
                    if (!c.active) {
                      c.start(c.chapterIndex);
                    } else if (c.paused) {
                      c.resume();
                    } else {
                      c.pause();
                    }
                  },
                ),
                IconButton(iconSize: 32, icon: const Icon(Icons.skip_next), onPressed: c.nextSegment),
                TextButton(onPressed: c.stop, child: const Text('关闭')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
