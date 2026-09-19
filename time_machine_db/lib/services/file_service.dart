import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Outcome of a [saveFiles] call.
sealed class FileResult {
  const FileResult();
}

/// The platform share sheet was opened (mobile and web).
class FileShared extends FileResult {
  const FileShared();
}

/// The file was copied to the chosen [path] (desktop).
class FileSaved extends FileResult {
  const FileSaved(this.path);

  final String path;
}

/// The user dismissed the destination picker, or there was nothing to save.
class FileCancelled extends FileResult {
  const FileCancelled();
}

/// Saves [files] to the platform.
///
/// Mobile and web use the native share sheet. Desktop platforms have no share
/// sheet for files, so the user is asked for a destination [dialogTitle] and
/// the file is copied there under the chosen name.
Future<FileResult> saveFiles({
  required List<XFile> files,
  String? text,
  String? dialogTitle,
}) async {
  if (files.isEmpty) {
    return const FileCancelled();
  }
  if (!_isDesktop) {
    await SharePlus.instance.share(ShareParams(files: files, text: text));
    return const FileShared();
  }

  final source = File(files.single.path);
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: p.basename(source.path),
  );
  if (path == null) {
    return const FileCancelled();
  }
  if (await source.exists()) {
    await source.copy(path);
  }
  return FileSaved(path);
}

/// Whether the platform has no native file share sheet, so files must be
/// written to a chosen destination instead.
bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);
