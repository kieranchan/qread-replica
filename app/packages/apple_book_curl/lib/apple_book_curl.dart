// apple_book_curl — the iOS page-curl page view of the reader's 仿真翻页(IOS原生). The native side (ios/Classes) registers the platform
// view [viewType] and answers on one method channel per view ([channelName]); lib/pages/read/pages/novel/apple_book.dart of the app
// drives it. Names follow the original's Runner (`AppleBookPageView`, `com.newread/apple_book_view`, `com.newread/apple_book_<id>`).
library;

/// The platform view type.
const String viewType = 'com.newread/apple_book_view';

/// The method channel of the view with platform view id [id].
String channelName(int id) => 'com.newread/apple_book_$id';
