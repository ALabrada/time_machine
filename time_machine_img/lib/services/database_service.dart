import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
      for (final entry in await _encodePicture(picture: original, name: 'then')) {
        archive.add(entry);
      }
    }
    if (picture != null) {
      for (final entry in await _encodePicture(picture: picture, name: 'now')) {
        archive.add(entry);
      }
    }
    final mainFile = ArchiveFile.string('meta.json', jsonEncode(record.toJson()));
    archive.add(mainFile);

    if (targetPath != null) {
      await Future.microtask(() => encoder.encodeStream(archive, OutputFileStream(targetPath)));
      return File(targetPath).readAsBytes();
    }

    final stream = OutputMemoryStream();
    await Future.microtask(() => encoder.encodeStream(archive, stream));
    return stream.getBytes();
  }

  Future<List<Record>> importFile({
    required String sourcePath,
  }) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeStream(InputFileStream(sourcePath));

    final meta = archive.findFile('meta.json');
    if (meta == null) {
      return [];
    }

    var record = await Future.microtask(() {
      final data = meta.readBytes();
      if (data == null) {
        return null;
      }
      final text = utf8.decode(data);
      return Record.fromJson(jsonDecode(text));
    });

    if (record == null) {
      return [];
    }

    record.original = await _decodePicture(
      archive: archive,
      name: 'then',
    );
    record.picture = await _decodePicture(
      archive: archive,
      name: 'now',
    );

    record = await createRepository<Record>().upsert(record);
    return [record];
  }

  Future<Picture?> _decodePicture({
    required Archive archive,
    required String name,
  }) async {
    final meta = archive.findFile('$name.json');
    if (meta == null) {
      return null;
    }
    final picture = await Future.microtask(() {
      final data = meta.readBytes();
      if (data == null) {
        return null;
      }
      final text = utf8.decode(data);
      return Picture.fromJson(jsonDecode(text));
    });
    if (picture == null) {
      return null;
    }

    final image = archive.findFile('$name.jpg');
    if (image == null) {
      return createRepository<Picture>().upsert(picture);
    }

    final id = picture.id;
    final dirPath = filePath;
    final localPath = '$dirPath/pictures/$id.jpg';
    await Future.microtask(() => image.decompress(OutputFileStream(localPath)));
    picture.url = Uri.file(localPath).toString();

    return await createRepository<Picture>().upsert(picture);
  }

  Future<List<ArchiveFile>> _encodePicture({
    required Picture picture,
    required String name,
  }) async {
    final url = Uri.tryParse(picture.url);
    final mainFile = ArchiveFile.string('$name.json', jsonEncode(picture.toJson()));
    if (url == null || url.scheme != 'file') {
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