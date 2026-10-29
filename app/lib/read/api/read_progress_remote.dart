// read/api/read_progress_remote.dart — the reading-progress calls of the account server (docs/API.md §Cloud sync):
//   `autopos`  {st:"0", tockenid, appid, book, index, pos, title, bid, t}   current position of a book (for "continue on another device")
//   `addreads` {tockenid, appid, book, readchapter, t}                      the set of chapters already read
//   `getpos`   {tockenid, appid, book, t}                                   the stored position (replica addition, see ProgressSync)
// Original: ReadApi 0xecd518 (autopos) and 0xecc0d0 (addreads); both are only sent when progress sync is switched on in the cloud
// settings (`autoSyncProgressEnabled`) and the user is logged in. Behind an interface so that unit tests and non-account builds can
// run without the network.
import '../../common/common.dart';
import '../../data/user.dart';
import '../../models/book.dart';
import '../../qread/http.dart';

abstract class ReadProgressRemote {
  Future<void> autoPos(Book book, int index, double pos);
  Future<void> addReads(Book book);

  /// The position the server holds for [book] (the last `autopos` of any device); null when nothing is stored or sync is off.
  Future<RemotePosition?> fetchPos(Book book);
}

/// A stored reading position as the server answers it (`getpos`).
class RemotePosition {
  final int index;
  final double pos;
  final String title;
  final String bid;
  final String appid;
  final int time;

  const RemotePosition({required this.index, required this.pos, this.title = '', this.bid = '', this.appid = '', this.time = 0});

  factory RemotePosition.fromJson(Map<String, dynamic> m) => RemotePosition(
        index: _int(m['index']),
        pos: _double(m['pos']),
        title: '${m['title'] ?? ''}',
        bid: '${m['bid'] ?? ''}',
        appid: '${m['appid'] ?? ''}',
        time: _int(m['t']),
      );

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static double _double(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  String toString() => 'RemotePosition($index, $pos, $appid)';
}

typedef ReadPost = Future<Map<String, dynamic>> Function(String url, Map<String, dynamic> body);

class ServerReadProgressRemote implements ReadProgressRemote {
  final ReadPost _post;
  final bool Function() _enabled;

  ServerReadProgressRemote({ReadPost? post, bool Function()? enabled})
      : _post = post ?? QHttp.post,
        _enabled = enabled ?? (() => UserSession.isLoggedIn && UserSession.autoSyncProgressEnabled);

  @override
  Future<void> autoPos(Book book, int index, double pos) async {
    if (!_enabled()) return;
    final r = await _post(Common.url('autopos'), {
      'st': '0',
      'tockenid': UserSession.tockenid,
      'appid': Common.appid,
      'book': book.bookUrl,
      'index': index,
      'pos': pos,
      'title': book.durChapterTitle,
      'bid': book.bid,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    _check(r);
  }

  @override
  Future<void> addReads(Book book) async {
    if (!_enabled()) return;
    final r = await _post(Common.url('addreads'), {
      'tockenid': UserSession.tockenid,
      'appid': Common.appid,
      'book': book.bookUrl,
      'readchapter': book.readchapter,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    _check(r);
  }

  @override
  Future<RemotePosition?> fetchPos(Book book) async {
    if (!_enabled()) return null;
    final r = await _post(Common.url('getpos'), {
      'tockenid': UserSession.tockenid,
      'appid': Common.appid,
      'book': book.bookUrl,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    final code = r['code'];
    if (code == -5 || code == '-5') return null; // nothing stored
    _check(r);
    final d = r['data'];
    return d is Map ? RemotePosition.fromJson(Map<String, dynamic>.from(d)) : null;
  }

  void _check(Map<String, dynamic> r) {
    final code = r['code'];
    if (code != 0 && code != '0') throw QHttpException('${r['errorMsg'] ?? '保存失败'}');
  }
}
