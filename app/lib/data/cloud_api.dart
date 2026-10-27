// data/cloud_api.dart — the small interface the data managers use to talk to the cloud-sync endpoints, so unit tests can plug in a
// fake and the app plugs in `UserApi` (api/userapi.dart, docs/API.md section 1 "Cloud sync").
//
// Result conventions (identical to `UserApi`): [etag] / [list] / [getItemJson] / [getItemMd5] return `''` when the server stores
// nothing; [updateUrl] returns `''` when the client's etag is current, the server etag when newer data exists and `'-1'` on
// failure (the sync switches are turned off by `UserApi` itself in that case). Real failures are thrown.
import '../api/userapi.dart';

abstract class CloudApi {
  Future<String> etag(CloudKind kind);
  Future<String> updateUrl(CloudKind kind, String etag);
  Future<String> list(CloudKind kind);
  Future<String> getItemJson(String item);
  Future<String> getItemMd5(String item);

  /// Uploads [content] as the item; [item] is `books|rss|sources|notes|groups` for the five synced lists, otherwise an item
  /// name such as `tts_engines`.
  Future<void> setItemJsonFile(String item, String content);
}

/// The production implementation over the static [UserApi] calls.
class UserApiCloud implements CloudApi {
  const UserApiCloud();

  @override
  Future<String> etag(CloudKind kind) => UserApi.cloudEtag(kind);

  @override
  Future<String> updateUrl(CloudKind kind, String etag) => UserApi.cloudUpdateUrl(kind, etag);

  @override
  Future<String> list(CloudKind kind) => UserApi.cloudList(kind);

  @override
  Future<String> getItemJson(String item) => UserApi.getItemJson(item);

  @override
  Future<String> getItemMd5(String item) => UserApi.getItemMd5(item);

  @override
  Future<void> setItemJsonFile(String item, String content) => UserApi.setItemJsonFile(item, content);
}

/// What the managers use when no API is injected.
CloudApi defaultCloudApi = const UserApiCloud();
