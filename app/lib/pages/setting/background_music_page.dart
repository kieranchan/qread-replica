// pages/setting/background_music_page.dart — 背景音乐 (`BackgroundMusicPage`, 15 functions): the imported tracks
// (data/background_music_manager.dart). Import → `导入成功` / `导入失败: …`; 重命名 (`请输入新名称`, `名称不能为空`, `重命名成功`);
// delete (`确定要删除 "x" 吗？` → `删除成功` / `删除失败: …`). Tap plays a preview; the check mark selects the track for reading and the
// slider sets the volume (0.1 .. 0.8). Empty: `暂无背景音乐`.
import 'package:flutter/material.dart';

import '../../data/background_music_manager.dart';
import '../../models/background_music.dart';
import '../../theme/widgets.dart';
import '../../util/audio/my_audio_player.dart';
import '../../util/toast.dart';

class BackgroundMusicPage extends StatefulWidget {
  const BackgroundMusicPage({super.key});

  static const List<String> extensions = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'];

  @override
  State<BackgroundMusicPage> createState() => _BackgroundMusicPageState();
}

class _BackgroundMusicPageState extends State<BackgroundMusicPage> {
  Myaudioplayer? _player;
  String _playing = '';
  double _volume = BackgroundMusicManager.volume;

  @override
  void initState() {
    super.initState();
    BackgroundMusicManager.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final f = await DeviceIo.pickFile(extensions: BackgroundMusicPage.extensions);
      if (f == null) return;
      await BackgroundMusicManager.add(f);
      Toast.show('导入成功');
    } catch (e) {
      Toast.show('导入失败: $e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _rename(BackgroundMusic m) async {
    final name = await Dialogs.input(context, '重命名', hint: '请输入新名称', initial: m.name);
    if (name == null) return;
    if (name.trim().isEmpty) return Toast.show('名称不能为空', iserror: true);
    await BackgroundMusicManager.rename(m.id, name.trim());
    Toast.show('重命名成功');
    if (mounted) setState(() {});
  }

  Future<void> _delete(BackgroundMusic m) async {
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除 "${m.name}" 吗？', danger: true)) return;
    try {
      if (_playing == m.id) await _stop();
      await BackgroundMusicManager.remove(m.id);
      Toast.show('删除成功');
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _player?.stop();
    setState(() => _playing = '');
  }

  Future<void> _toggle(BackgroundMusic m) async {
    if (_playing == m.id) return _stop();
    try {
      final p = _player ??= Myaudioplayer();
      await p.stop();
      await p.setFile(BackgroundMusicManager.filePath(m));
      await p.setVolume(_volume);
      await p.setLoop(true);
      await p.play();
      setState(() => _playing = m.id);
    } catch (e) {
      Toast.show('$e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = BackgroundMusicManager.musics;
    final selected = BackgroundMusicManager.selectedId;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('背景音乐'), actions: [
        IconButton(key: const Key('music_import'), tooltip: '导入', icon: const Icon(Icons.library_music_outlined), onPressed: _import),
      ]),
      body: Column(children: [
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: Slider(
            min: BackgroundMusicManager.minVolume,
            max: BackgroundMusicManager.maxVolume,
            value: _volume,
            onChanged: (v) => setState(() => _volume = v),
            onChangeEnd: (v) async {
              await BackgroundMusicManager.setVolume(v);
              await _player?.setVolume(v);
            },
          ),
          trailing: Text(_volume.toStringAsFixed(1)),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('暂无背景音乐', style: TextStyle(color: cs.outline)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = list[i];
                    return ListTile(
                      leading: IconButton(
                        icon: Icon(_playing == m.id ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                        onPressed: () => _toggle(m),
                      ),
                      title: Text(m.name),
                      onTap: () async {
                        await BackgroundMusicManager.select(selected == m.id ? '' : m.id);
                        setState(() {});
                      },
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (selected == m.id) Icon(Icons.check, color: cs.primary),
                        PopupMenuButton<String>(
                          onSelected: (v) => v == 'rename' ? _rename(m) : _delete(m),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
