// pages/user/account_validators.dart — the field checks of the account pages, with the original's texts:
//   login 0x7b876c / register 0x7f3480: `用户名至少2个字符`; register 0x7f3370 / forgot 0x7b58cc: the e-mail regex and
//   `请输入有效的邮箱地址`; register 0x7f300c: `请确认密码` / `两次输入的密码不一致`; change password 0x88091c / 0x880a58:
//   `密码至少6位`, `新密码不能与当前密码相同`.
// (The original also refused 163.com / 126.com addresses — `暂不支持当前邮箱，建议使用qq邮箱` — a limit of qread.xyz's mailer; the
// owner's server sends nothing by mail, so every valid address is accepted here.)
abstract class AccountValidators {
  static final RegExp emailRe = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$');

  /// null when fine, else the message to show.
  static String? username(String s, {String empty = '请输入用户名'}) {
    final v = s.trim();
    if (v.isEmpty) return empty;
    if (v.length < 2) return '用户名至少2个字符';
    return null;
  }

  static String? email(String s) {
    final v = s.trim();
    if (v.isEmpty) return '请输入邮箱地址';
    if (!emailRe.hasMatch(v)) return '请输入有效的邮箱地址';
    return null;
  }

  static String? password(String s, {String empty = '请输入密码'}) {
    if (s.isEmpty) return empty;
    if (s.length < 6) return '密码至少6位';
    return null;
  }

  static String? confirm(String password, String again, {String empty = '请确认密码'}) {
    if (again.isEmpty) return empty;
    if (again != password) return '两次输入的密码不一致';
    return null;
  }

  static String? newPassword(String current, String next) {
    final e = password(next, empty: '请输入新密码');
    if (e != null) return e;
    if (next == current) return '新密码不能与当前密码相同';
    return null;
  }
}
