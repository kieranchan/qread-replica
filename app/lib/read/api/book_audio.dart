// read/api/book_audio.dart — class 1512 `BookAudio` (0x10 bytes, no recovered members): the per-book location of downloaded audio
// chapters. The audio pages (`pages/read/pages/audio_view.dart`, TTS) own the playback; this only names the folder
// `<documents>/audio2/<md5(bookUrl)>/` they use.
import 'dart:io';

import 'read_file_store.dart';
import 'read_storage_root.dart';

class BookAudio {
  static const String dirName = 'audio2';

  const BookAudio();

  /// `<root>/audio2/<md5(bookUrl)>` (not created).
  Directory dirFor(String bookUrl) => Directory('${ReadStorageRoot.sub(dirName).path}/${ReadFileStore.md5Hex(bookUrl)}');

  File fileFor(String bookUrl, int chapterIndex, {String ext = 'mp3'}) => File('${dirFor(bookUrl).path}/$chapterIndex.$ext');

  Future<void> deleteBook(String bookUrl) async {
    final d = dirFor(bookUrl);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
