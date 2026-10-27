// util/vip.dart — the member gate every member-only feature uses: `if (!isvip) toast("…为会员功能")`.
import '../data/user.dart';
import 'toast.dart';

abstract class Vip {
  /// True when the action may proceed. Shows the original's message otherwise (default text of the cloud settings page).
  static bool require([String message = '此功能为会员功能']) {
    if (UserSession.isvip) return true;
    Toast.show(message);
    return false;
  }
}
