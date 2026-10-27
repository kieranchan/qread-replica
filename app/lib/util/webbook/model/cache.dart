// util/webbook/model/cache.dart - `Cache` row (key, value, deadline) of the rule engine's key/value store (models_fields.tsv:
// toJson@0x17d4d8, fromJson@0x17d26c).
import '../../json.dart';

class Cache {
  String key;
  Object? value;

  /// Epoch milliseconds after which the entry is invalid; 0 = never.
  int deadline;

  Cache({this.key = '', this.value, this.deadline = 0});

  factory Cache.fromJson(Map<String, dynamic> json) => Cache(
        key: jsonutil.asString(json['key']),
        value: json['value'],
        deadline: jsonutil.asInt(json['deadline']),
      );

  Map<String, dynamic> toJson() => {'key': key, 'value': value, 'deadline': deadline};

  bool get isExpired => deadline != 0 && deadline < DateTime.now().millisecondsSinceEpoch;
}
