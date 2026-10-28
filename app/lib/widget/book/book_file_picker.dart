// widget/book/book_file_picker.dart — file picking behind an interface (the plugin needs a device; tests set
// [BookFilePicker.instance] to a fake). Original dialog titles: 「请选择您想要导入的小说文件」 (txt / epub / pdf / mobi,
// 0xf78ca8) and 「请选择您想要导入的文件」 (json, 0xf75494).
import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract class BookFilePicker {
  static BookFilePicker instance = PluginBookFilePicker();

  /// Book files chosen by the user (empty when cancelled).
  Future<List<File>> pickBooks();

  /// One JSON file (progress import), null when cancelled.
  Future<File?> pickJson();

  /// One image (book cover 「上传图片」), null when cancelled.
  Future<File?> pickImage();
}

class PluginBookFilePicker implements BookFilePicker {
  /// The original's list (0xf78ca8, `".pdf"` 0xf792cc) plus the Kindle variants the reading core also imports.
  static const List<String> bookExtensions = ['txt', 'epub', 'pdf', 'mobi', 'azw', 'azw3', 'prc'];

  @override
  Future<List<File>> pickBooks() async {
    final files = await FilePicker.pickFiles(dialogTitle: '请选择您想要导入的小说文件', type: FileType.custom, allowedExtensions: bookExtensions);
    return [
      for (final f in files)
        if (f.path != null) File(f.path!)
    ];
  }

  @override
  Future<File?> pickJson() async {
    final f = await FilePicker.pickFile(dialogTitle: '请选择您想要导入的文件', type: FileType.custom, allowedExtensions: const ['json']);
    return f?.path == null ? null : File(f!.path!);
  }

  @override
  Future<File?> pickImage() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    return f?.path == null ? null : File(f!.path!);
  }
}
