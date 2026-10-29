// pages/user/cloud_setting_page.dart — 云端设置 (original 0x5ce284; 开始同步 0x5d3378 / 0x907a6c; the 删除云端数据 flows
// 0xfcd918 / 0xfcb99c / 0xfc901c / 0xfcad6c / 0xfcc210; the merges 0xfcc414 `正在合并云端书架` …).
// Every switch is member-only (`此功能为会员功能`) and turning one on asks the server (`canOpenCloud`), which is the real permission
// check on the owner's server. Each switch carries the original's explanation and note; switching one on merges the cloud copy at
// once; 开始同步 runs every enabled sync and `上次同步` shows when; 删除云端数据 empties the server items of a kind (only while its
// switch is off). The 云端仓库 (WebDAV book repository) part of the original page is not ported (docs/GAPS.md).
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../data/bookself.dart';
import '../../data/cloud/cloud_books.dart';
import '../../data/cloud_api.dart';
import '../../data/cloud_sync.dart';
import '../../data/note_data_n.dart';
import '../../data/rss.dart';
import '../../data/source.dart';
import '../../data/svg.dart';
import '../../data/tts.dart';
import '../../data/user.dart';
import '../../data/webdav.dart';
import '../../models/webdavserver.dart';
import '../../qread/http.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';

class CloudKindInfo {
  final String key;
  final String title;
  final String subtitle;
  final String note;

  /// The server items this kind lives in (emptied by 删除云端数据).
  final List<String> items;
  const CloudKindInfo(this.key, this.title, this.subtitle, this.note, this.items);

  bool get enabled => switch (key) {
        PrefKeys.cloudbookself => UserSession.cloudbookself,
        PrefKeys.cloudsource => UserSession.cloudsource,
        PrefKeys.cloudmark => UserSession.cloudmark,
        PrefKeys.cloudtheme => UserSession.cloudtheme,
        PrefKeys.cloudtts => UserSession.cloudtts,
        _ => false,
      };
}

class CloudSettingPage extends StatefulWidget {
  const CloudSettingPage({super.key});

  static const List<CloudKindInfo> kinds = [
    CloudKindInfo(
      PrefKeys.cloudbookself,
      '云端书架',
      '将书架放在云端以达到同账号下所有设备书架一致，如无需多端书架一致请勿开启',
      '云端书架和书架备份不通用，如果需要将书架备份的书导入云端书架，可以先打开云端书架再导入书架备份，打开云端书架时会将本地书架和云端进行合并。',
      ['books', 'groups'],
    ),
    CloudKindInfo(
      PrefKeys.cloudtts,
      '云端朗读引擎',
      '将朗读引擎同步到云端以达到同账号下所有设备引擎一致，本地引擎文件不会同步，需自行导入',
      '云端朗读引擎会同步全部引擎。注意：本地引擎（导入的模型包）依赖本机文件，同步到其它设备后无法使用，需要自行在被同步设备重新导入模型包。引擎所有接口密钥保存在本机，不会同步。打开时本地引擎与云端按名称合并（同名以云端为准），开启后以云端为准同步，一端删除会在其它设备同步删除。关闭时本地数据不变。',
      ['tts_engines'],
    ),
    CloudKindInfo(
      PrefKeys.cloudsource,
      '云端书源',
      '将书源订阅源放在云端以达到同账号下所有设备书源一致，如无需多端书源一致请勿开启',
      '云端书源和书源备份不通用，如果需要将书源备份的书导入云端书源，可以先打开云端书源再导入书源备份，打开云端书源时会将本地和云端合并。',
      ['sources', 'rss'],
    ),
    CloudKindInfo(PrefKeys.cloudtheme, '云端排版', '将排版和自定义气泡放置云端，以达到多端同步', '', ['svg']),
    CloudKindInfo(PrefKeys.cloudmark, '云端书签', '将浏览器书签放置云端，以达到多端同步', '', ['notes']),
  ];

  /// The server's permission check (tests replace it).
  static Future<bool> Function() canOpenCloud = UserApi.canOpenCloud;

  /// The merge / sync of each kind (tests replace them).
  static Map<String, Future<void> Function()> syncOf = {
    PrefKeys.cloudbookself: () async {
      await Groupdata.syncCloud();
      await BookSelfN.syncCloud();
    },
    PrefKeys.cloudsource: () async {
      await Sources.syncCloud();
      await RssSources.syncCloud();
    },
    PrefKeys.cloudmark: () async => NoteDataN.syncCloud(),
    PrefKeys.cloudtheme: () async => Svg.pullCloud(),
    PrefKeys.cloudtts: () async => CloudTts.sync(),
  };

  static String get lastSync => Storage.getString(PrefKeys.lastSyncTime);

  @override
  State<CloudSettingPage> createState() => _CloudSettingPageState();
}

class _CloudSettingPageState extends State<CloudSettingPage> {
  bool _syncing = false;
  bool _repoSyncing = false;
  WebDavServer? _repoServer;
  CloudBooksSettings _repo = CloudBooks.load();

  @override
  void initState() {
    super.initState();
    _loadRepo();
  }

  Future<void> _loadRepo() async {
    final srv = await CloudBooks.server();
    if (mounted) {
      setState(() {
        _repo = CloudBooks.load();
        _repoServer = srv;
      });
    }
  }

  // ------------------------------------------------------------------ 云端仓库 (0x5ce284 WebDAV section)

  /// 选择 WebDAV 服务器: one of the 网盘管理 entries, the account server's own store (configured here), or none.
  Future<void> _pickRepoServer() async {
    await WebDav.load();
    final servers = WebDav.servers.where((e) => e.id != CloudBooks.ownServerId).toList();
    final options = ['使用轻阅读账号服务器（自动配置）', for (final e in servers) e.name.isEmpty ? e.url : e.name, '不使用云端仓库'];
    final current = _repo.serverId == CloudBooks.ownServerId ? 0 : (servers.indexWhere((e) => e.id == _repo.serverId) + 1);
    if (!mounted) return;
    final i = await Dialogs.choose(context, '选择 WebDAV 服务器', options, selected: current <= 0 ? null : current);
    if (i == null) return;
    try {
      if (i == 0) {
        if (!Vip.require()) return;
        await CloudBooks.useOwnServer();
      } else if (i == options.length - 1) {
        await CloudBooks.save(_repo..serverId = '');
      } else {
        await CloudBooks.save(_repo..serverId = servers[i - 1].id);
      }
      await _loadRepo();
      if (_repoServer != null) Toast.show('已选择 WebDAV 服务器：${_repoServer!.name}');
    } catch (e) {
      Toast.show('保存云端书籍WebDAV设置失败: $e', iserror: true);
    }
  }

  /// 设置备份目录 (0x5d3ab0).
  Future<void> _editBackupDir() async {
    final v = await Dialogs.input(context, '设置备份目录', hint: '请输入 WebDAV 服务器上的备份目录路径：', initial: _repo.backupDir);
    if (v == null) return;
    final dir = CloudBooks.normalizeDir(v.isEmpty ? CloudBooks.defaultDir : v);
    try {
      await CloudBooks.save(_repo..backupDir = dir);
      await _loadRepo();
    } catch (e) {
      Toast.show('保存云端书籍WebDAV设置失败: $e', iserror: true);
    }
  }

  /// 同步云端仓库 (0xfc7ac8): `请先选择 WebDAV 服务器` / `同步完成` / `同步失败: …`.
  Future<void> _syncRepo() async {
    if (_repoServer == null) return Toast.show('请先选择 WebDAV 服务器');
    if (CloudBooks.syncing) return Toast.show('同步正在进行中，请稍候...');
    setState(() => _repoSyncing = true);
    try {
      final r = await CloudBooks.sync();
      Toast.show(r.errors.isEmpty ? '同步完成，上传了 ${r.uploaded} 个文件，删除了 ${r.deleted} 个文件' : '同步失败: ${r.errors.first}', iserror: r.errors.isNotEmpty);
    } catch (e) {
      Toast.show('同步失败: $e', iserror: true);
    } finally {
      if (mounted) setState(() => _repoSyncing = false);
      await _loadRepo();
    }
  }

  Future<void> _toggle(CloudKindInfo c, bool value) async {
    if (value && !Vip.require()) return;
    if (value) {
      try {
        if (!await CloudSettingPage.canOpenCloud()) return Toast.show('云端功能需要会员权限', iserror: true);
      } on QHttpException catch (e) {
        return Toast.show(e.message, iserror: true);
      }
    }
    await UserSession.setSwitch(c.key, value);
    if (!value) return;
    // 0xfcc414 …: switching on merges the cloud copy right away
    Toast.show('正在合并${c.title}');
    try {
      await CloudSettingPage.syncOf[c.key]?.call();
    } catch (e) {
      Toast.show('${c.title}合并失败: $e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  /// 删除云端数据 (0xfcd918 …): only while the switch is off and for members; the kind's items are emptied on the server.
  Future<void> _deleteCloud(CloudKindInfo c) async {
    if (c.enabled) return Toast.show('请先关闭${c.title}');
    if (!UserSession.isvip) return Toast.show('此功能为会员功能');
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除${c.title}所有数据吗？', danger: true)) return;
    try {
      for (final item in c.items) {
        await defaultCloudApi.setItemJsonFile(item, '[]');
      }
      Toast.show('删除成功');
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
  }

  /// 开始同步 (0x5d3378): every enabled kind in turn; `同步时间已更新` afterwards.
  Future<void> _syncAll() async {
    if (_syncing) return Toast.show('同步进行中...');
    setState(() => _syncing = true);
    final failed = <String>[];
    try {
      for (final c in CloudSettingPage.kinds) {
        if (!c.enabled) continue;
        try {
          await CloudSettingPage.syncOf[c.key]?.call();
        } catch (e) {
          failed.add('${c.title}: $e');
        }
      }
      if (_repoServer != null && !CloudBooks.syncing) {
        try {
          await CloudBooks.sync();
        } catch (e) {
          failed.add('云端仓库: $e');
        }
        await _loadRepo();
      }
      await Storage.setString(PrefKeys.lastSyncTime, CloudSync.formatTime(DateTime.now()));
      Toast.show(failed.isEmpty ? '同步时间已更新' : '同步失败 ${failed.join('；')}', iserror: failed.isNotEmpty);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: cs.outline);
    return ValueListenableBuilder<int>(
      valueListenable: UserSession.revision,
      builder: (context, _, _) {
        final last = CloudSettingPage.lastSync;
        return Scaffold(
          appBar: AppBar(title: const Text('云端设置')),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('云端功能需要会员权限，开启后将自动同步数据到云端，确保多设备数据一致', style: TextStyle(color: cs.outline)),
            ),
            for (final c in CloudSettingPage.kinds) ...[
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              SwitchListTile(
                key: Key('sw_${c.key}'),
                title: Text('启用${c.title}'),
                subtitle: Text(c.subtitle, style: small),
                value: c.enabled,
                onChanged: (x) => _toggle(c, x),
              ),
              if (c.note.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), child: Text(c.note, style: small)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(key: Key('del_${c.key}'), onPressed: () => _deleteCloud(c), child: const Text('删除云端数据')),
              ),
              const Divider(height: 1),
            ],
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('云端仓库', style: const TextStyle(fontWeight: FontWeight.w600))),
            ListTile(
              key: const Key('repo_server'),
              title: const Text('选择 WebDAV 服务器'),
              subtitle: Text(_repoServer == null ? '未选择 WebDAV 服务器' : '已选择 WebDAV 服务器：${_repoServer!.name}', style: small),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRepoServer,
            ),
            ListTile(
              key: const Key('repo_dir'),
              title: Text('备份目录: ${_repo.backupDir}'),
              subtitle: Text('该目录将用于存储备份的书籍文件', style: small),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editBackupDir,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('打开云端仓库后会将本地书本备份到 webdav，同时打开云端仓库和云端书架功能可以在多设备保持书架一致。', style: small),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text('上次同步: ${_repo.lastSyncTime.isEmpty ? '从未' : _repo.lastSyncTime}', style: small)),
                FilledButton.tonal(key: const Key('repo_sync_now'), onPressed: _repoSyncing ? null : _syncRepo, child: Text(_repoSyncing ? '同步中...' : '同步云端仓库')),
              ]),
            ),
            const Divider(height: 1),
            SwitchListTile(
              key: const Key('sw_${PrefKeys.autoSyncProgressEnabled}'),
              title: const Text('进度同步'),
              subtitle: Text('阅读进度实时同步到云端，打开书时与其它设备的进度比对（进度同步确认）', style: small),
              value: UserSession.autoSyncProgressEnabled,
              onChanged: (x) async {
                if (x && !Vip.require()) return;
                await UserSession.setSwitch(PrefKeys.autoSyncProgressEnabled, x);
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Text('上次同步: ${last.isEmpty ? '从未' : last}', style: small)),
                FilledButton(
                  key: const Key('cloud_sync_now'),
                  onPressed: _syncing || !UserSession.isLoggedIn ? null : _syncAll,
                  child: Text(_syncing ? '同步中...' : '开始同步'),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
