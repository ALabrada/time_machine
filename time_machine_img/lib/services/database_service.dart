import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:time_machine_db/time_machine_db.dart';

extension DatabaseExtensions on DatabaseService {
  Future<Uint8List?> export({
    required Record record,
    String? targetPath,
  }) async {
    final archive = Archive();
    final encoder = ZipEncoder();
    final original = record.original;
    final picture = record.picture;
    if (original != null) {
      for (final entry in await _archivePicture(picture: original, name: 'then')) {
        archive.add(entry);
      }
    }
    if (picture != null) {
      for (final entry in await _archivePicture(picture: picture, name: 'now')) {
        archive.add(entry);
      }
    }
    final mainFile = ArchiveFile.string('meta.json', jsonEncode(record.toJson()));
    archive.add(mainFile);

    final stream = OutputMemoryStream();
    await Future.microtask(() => encoder.encodeStream(archive, stream));
    return stream.getBytes();
  }

  Future<List<ArchiveFile>> _archivePicture({
    required Picture picture,
    required String name,
  }) async {
    final url = Uri.tryParse(picture.url);
    final mainFile = ArchiveFile.string('$name.json', jsonEncode(picture.toJson()));
    if (url == null || url.scheme != 'files') {
      return [mainFile];
    }
    final attachment = File(url.path);
    final size = await attachment.length();
    final content = FileContentStream(InputFileStream(attachment.path));
    final attachmentFile = ArchiveFile.file('$name.jpg', size, content);
    return [
      mainFile,
      attachmentFile,
    ];
  }
}