import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:uuid/uuid.dart';

extension DatabaseExtensions on DatabaseService {
  Future<List<Record>> findRecords(List<String> words) async {
    if (words.isEmpty) {
      return await createRepository<Record>().list();
    }

    final pictures = await createRepository<Picture>().findPicturesWithText(words);
    final pictureIds = List.generate(pictures.length, (i) => pictures[i].localId!);
    final records = await createRepository<Record>().findRecordsWithPictures(pictureIds);
    return records;
  }

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
    await Future.microtask(() => encoder.encodeStream(archive, stream,
      level: DeflateLevel.defaultCompression,
    ));
    return stream.getBytes();
  }

  Future<Uint8List?> exportMany({
    required List<Record> records,
    String? targetPath,
  }) async {
    final archive = Archive();
    final encoder = ZipEncoder();
    if (records.isEmpty) {
      return null;
    }

    for (final record in records) {
      final original = record.original;
      final picture = record.picture;
      final path = Uuid().v4();
      archive.add(ArchiveFile.directory(path));
      if (original != null) {
        for (final entry in await _encodePicture(picture: original, name: '$path/then')) {
          archive.add(entry);
        }
      }
      if (picture != null) {
        for (final entry in await _encodePicture(picture: picture, name: '$path/now')) {
          archive.add(entry);
        }
      }
      final mainFile = ArchiveFile.string('$path/meta.json', jsonEncode(record.toJson()));
      archive.add(mainFile);
    }

    if (targetPath != null) {
      await Future.microtask(() => encoder.encodeStream(archive, OutputFileStream(targetPath)));
      return File(targetPath).readAsBytes();
    }

    final stream = OutputMemoryStream();
    await Future.microtask(() => encoder.encodeStream(archive, stream,
      level: DeflateLevel.defaultCompression,
    ));
    return stream.getBytes();
  }

  Future<List<Record>> importFile({
    required String sourcePath,
  }) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeStream(InputFileStream(sourcePath));

    var record = await _importRecord(archive: archive);
    if (record != null) {
      return [record];
    }

    return await Stream.fromIterable(archive.files)
      .where((e) => e.isDirectory)
      .asyncMap((e) => _importRecord(archive: archive, path: e.name))
      .whereNotNull()
      .toList();
  }

  Future<bool> removeRecord(Record record) async {
    final recordId = record.localId;
    if (recordId == null || !await createRepository<Record>().delete(recordId)) {
      return false;
    }

    if (!await createRepository<Picture>().delete(record.pictureId)) {
      return false;
    }

    final url = Uri.tryParse(record.picture?.url ?? '');
    if (url != null) {
      await File(url.path).delete();
    }
    return true;
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

  Future<Record?> _importRecord({
    required Archive archive,
    String path = '',
  }) async {
    final meta = archive.findFile('${path}meta.json');
    if (meta == null) {
      return null;
    }

    var record = await Future.microtask(() {
      final data = meta.readBytes();
      if (data == null) {
        return null;
      }
      final text = utf8.decode(data);
      return Record.fromJson(jsonDecode(text));
    });

    final picture = await _decodePicture(
      archive: archive,
      name: '${path}now',
    );

    if (record == null || picture == null) {
      return null;
    }

    record.picture = picture;
    record.pictureId = picture.localId!;

    record.original = await _decodePicture(
      archive: archive,
      name: '${path}then',
    );
    record.originalId = record.original?.localId;

    record = await createRepository<Record>().upsert(record);
    return record;
  }
}