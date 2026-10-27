// read/api/read_progress_remote.dart — the two reading-progress calls of the account server (docs/API.md §Cloud sync):
//   `autopos`  {st:"0", tockenid, appid, book, index, pos, bid, t}   current position of a book (for "continue on another device")
//   `addreads` {tockenid, appid, book, readchapter, t}               the set of chapters already read
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

  void _check(Map<String, dynamic> r) {
    final code = r['code'];
    if (code != 0 && code != '0') throw QHttpException('${r['errorMsg'] ?? '保存失败'}');
  }
}
