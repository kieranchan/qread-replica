// models/userinfo.dart — the account record returned by `login` and `getUserInfo`.
//
// Slot order follows the original (applyUserinfo, docs/API.md): username, id, token, email, nickname, avatar, isvip.
// The server sends the session token under the JSON key `vip` (a String); `tockenid` is accepted as an alias.

class Userinfo {
  final String username;
  final String id;
  final String tockenid;
  final String email;
  final String nickname;
  final String avatarUrl;
  final bool isvip;

  /// Extra, not part of the original model: expiry date shown on the 会员中心 / me page (`vipExpire`, yyyy-MM-dd).
  final String vipExpire;

  const Userinfo({
    required this.username,
    required this.id,
    required this.tockenid,
    required this.email,
    required this.nickname,
    required this.avatarUrl,
    required this.isvip,
    this.vipExpire = '',
  });

  factory Userinfo.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v == null ? '' : v.toString();
    final username = s(json['username']);
    final nick = s(json['nickname']);
    return Userinfo(
      username: username,
      id: s(json['id']),
      tockenid: s(json['vip'] ?? json['tockenid']),
      email: s(json['email']),
      nickname: nick.isEmpty ? username : nick,
      avatarUrl: s(json['avatar_url']),
      isvip: json['isvip'] == true,
      vipExpire: s(json['vipExpire']),
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'id': id,
        'vip': tockenid,
        'email': email,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'isvip': isvip,
        'vipExpire': vipExpire,
      };
}
