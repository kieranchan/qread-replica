// models/userinfo.dart — the account record returned by `login` and `getUserInfo`.
//
// Slot order of the original (verified in the decompiled login/getUserInfo constructors and applyUserinfo, docs/API.md):
//   username, vip, id, email, nickname, avatar_url, isvip
// where the JSON key `id` is the SESSION TOKEN (the app stores that slot as `tockenid`) and `vip` is a display string for the
// membership ("永久", a date, or empty). There is no separate numeric user id in the original model.

class Userinfo {
  final String username;

  /// JSON `vip`: membership text shown in the UI (`永久` hides the 立即开通 button).
  final String vip;

  /// JSON `id`: the session token sent as `tockenid` with every request.
  final String tockenid;
  final String email;
  final String nickname;
  final String avatarUrl;
  final bool isvip;

  const Userinfo({
    required this.username,
    required this.vip,
    required this.tockenid,
    required this.email,
    required this.nickname,
    required this.avatarUrl,
    required this.isvip,
  });

  factory Userinfo.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v == null ? '' : v.toString();
    final username = s(json['username']);
    final nick = s(json['nickname']);
    return Userinfo(
      username: username,
      vip: s(json['vip']),
      tockenid: s(json['id']),
      email: s(json['email']),
      nickname: nick.isEmpty ? username : nick,
      avatarUrl: s(json['avatar_url']),
      isvip: json['isvip'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'vip': vip,
        'id': tockenid,
        'email': email,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'isvip': isvip,
      };
}
