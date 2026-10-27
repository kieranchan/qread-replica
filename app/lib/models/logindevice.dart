// models/logindevice.dart — one logged-in device (`getloginDevice`), and models/autodevice.dart's backup device.
class LoginDevice {
  final String appid;
  final String platform;
  final String model;
  final int time;

  const LoginDevice({required this.appid, required this.platform, required this.model, required this.time});

  factory LoginDevice.fromJson(Map<String, dynamic> j) => LoginDevice(
        appid: '${j['appid'] ?? ''}',
        platform: '${j['platform'] ?? ''}',
        model: '${j['model'] ?? ''}',
        time: j['time'] is int ? j['time'] as int : 0,
      );

  Map<String, dynamic> toJson() => {'appid': appid, 'platform': platform, 'model': model, 'time': time};
}

/// models/autodevice.dart: `model, platform, appid` (a backup device).
class Autodevice {
  final String model;
  final String platform;
  final String appid;

  const Autodevice({required this.model, required this.platform, required this.appid});

  factory Autodevice.fromJson(Map<String, dynamic> j) =>
      Autodevice(model: '${j['model'] ?? ''}', platform: '${j['platform'] ?? ''}', appid: '${j['appid'] ?? ''}');

  Map<String, dynamic> toJson() => {'model': model, 'platform': platform, 'appid': appid};
}
