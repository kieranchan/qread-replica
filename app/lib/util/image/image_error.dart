// util/image/image_error.dart — class 1330 `ImageError` (abstract, `static Map<String, String> urls` 0x4ca0): the images that failed to load
// in this session (url -> error text) so that the reader shows the error placeholder at once instead of retrying a dead link on every
// page turn.
abstract class ImageError {
  static final Map<String, String> urls = {};

  static void mark(String url, String error) => urls[url] = error;

  static bool failed(String url) => urls.containsKey(url);

  static String? messageOf(String url) => urls[url];

  /// Forget one url (user pressed "retry") or all of them.
  static void clear([String? url]) => url == null ? urls.clear() : urls.remove(url);
}
