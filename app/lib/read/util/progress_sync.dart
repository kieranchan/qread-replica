// read/util/progress_sync.dart — 进度同步确认 (original ReadApi 0xecac28 with the dialog 0x2473fc): when a book is opened the position
// the server holds is compared with this device's; when they differ the reader asks
//   进度同步确认 / 检测到进度不一致，请选择同步方式：  with the two rows 当前设备进度 / 云端同步进度 and the buttons 取消 · 覆盖 · 跳转
// 覆盖 uploads this device's position, 跳转 opens the server's chapter at its position. The original logs `保存服务器记录 : i, pos`
// and `不一致` on the way and compared against the record of the bound 轻阅读后端 (`/saveBookProgress`); the replica's positions
// live on the account server (`autopos`), so the comparison is made there (`getpos`), once per book per app session, and only
// against a record written by another device (this device's own record can only be older than what the book already holds).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../common/common.dart';
import '../../models/book.dart';
import '../../pages/read/pages/novel/views/reader_host.dart';
import '../api/read_progress_remote.dart';
import '../api/readapi.dart';

enum ProgressSyncChoice { overwrite, jump }

abstract class ProgressSync {
  static final Set<String> _checked = {};

  /// This device (records with the same appid are skipped); tests replace it.
  static String Function() deviceId = () => Common.appid;

  /// Positions closer than this (1/100 of a chapter) count as the same.
  static const double posTolerance = 0.01;

  static void reset() => _checked.clear();

  static bool differs(Book book, RemotePosition remote) {
    if (remote.appid.isNotEmpty && remote.appid == deviceId()) return false;
    return remote.index != book.durChapterIndex || (remote.pos - book.durChapterPos).abs() >= posTolerance;
  }

  /// The server's position when it is another device's and differs from [api]'s book; null otherwise (and for local books,
  /// without a remote, or when the server cannot be reached — a failed check never blocks reading).
  static Future<RemotePosition?> fetchDifferent(ReadApi api) async {
    final remote = ReadApi.remote;
    if (remote == null || ReadApi.isLocalBook(api.book)) return null;
    final RemotePosition? p;
    try {
      p = await remote.fetchPos(api.book);
    } catch (e) {
      ReadApi.log?.call('获取服务器进度失败: $e');
      return null;
    }
    if (p == null) return null;
    ReadApi.log?.call('保存服务器记录 : ${p.index}, ${p.pos}');
    if (!differs(api.book, p)) return null;
    ReadApi.log?.call('不一致');
    return p;
  }

  /// Carries out the user's choice: 覆盖 re-uploads this device's position, 跳转 opens the server's one (clamped to the catalog)
  /// and saves it as the new position.
  static Future<void> apply(ReadApi api, ProgressSyncChoice? choice, RemotePosition remote, {required Future<void> Function(int index, double pos) jump}) async {
    final book = api.book;
    switch (choice) {
      case null:
        return;
      case ProgressSyncChoice.overwrite:
        await api.saveProgress(chapterIndex: book.durChapterIndex, pos: book.durChapterPos, markRead: false);
      case ProgressSyncChoice.jump:
        if (api.chapters.isEmpty) return;
        final index = remote.index.clamp(0, api.chapters.length - 1);
        final pos = remote.pos.clamp(0.0, 1.0);
        await jump(index, pos);
        await api.saveProgress(chapterIndex: index, pos: pos, markRead: false);
    }
  }

  /// The whole check for an open reader: fetch, compare, ask, apply. Runs once per book per session; [context] gives the reader's
  /// context while it is still mounted.
  static Future<void> run(ReaderHost host, {required BuildContext? Function() context, Duration delay = const Duration(milliseconds: 800)}) async {
    final api = host.api;
    if (!_checked.add(host.book.bookUrl)) return;
    final remote = await fetchDifferent(api);
    if (remote == null) return;
    await Future<void>.delayed(delay);
    final ctx = context();
    if (ctx == null) return;
    final book = host.book;
    final choice = await showDialog<ProgressSyncChoice>(
      // ignore: use_build_context_synchronously — the reader handed out its context after the wait, while still mounted
      context: ctx,
      builder: (_) => ProgressSyncDialog(
        local: _label(book.durChapterIndex, book.durChapterTitle, book.durChapterPos),
        remote: _label(remote.index, remote.title.isNotEmpty ? remote.title : _chapterName(host, remote.index), remote.pos),
      ),
    );
    await apply(api, choice, remote, jump: (i, p) => host.jumpToChapter(i, progress: p));
  }

  static String _chapterName(ReaderHost host, int index) =>
      index >= 0 && index < host.chapters.length ? host.chapters[index].name : '';

  static String _label(int index, String title, double pos) {
    final t = title.trim();
    return '第${index + 1}章${t.isEmpty ? '' : ' $t'}  ${(pos * 100).toStringAsFixed(1)}%';
  }
}

/// The confirmation (0x2473fc): title 进度同步确认, the two progress rows and 取消 / 覆盖 / 跳转.
class ProgressSyncDialog extends StatelessWidget {
  final String local;
  final String remote;
  const ProgressSyncDialog({super.key, required this.local, required this.remote});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('进度同步确认', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 15), child: Text('检测到进度不一致，请选择同步方式：', style: TextStyle(fontSize: 14))),
          _item(context, '当前设备进度', local),
          const SizedBox(height: 8),
          _item(context, '云端同步进度', remote),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(key: const Key('progress_sync_overwrite'), onPressed: () => Navigator.of(context).pop(ProgressSyncChoice.overwrite), child: const Text('覆盖')),
        TextButton(key: const Key('progress_sync_jump'), onPressed: () => Navigator.of(context).pop(ProgressSyncChoice.jump), child: const Text('跳转')),
      ],
    );
  }

  Widget _item(BuildContext context, String title, String text) => Container(
        width: double.maxFinite,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}
