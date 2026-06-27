import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:uuid/uuid.dart';

extension DatabaseExtensions on DatabaseService {
  static String _expandPath(String path, String? filePath) {
    if (filePath == null) return path;
    return Uri.decodeFull(path).replaceAll(DatabaseService.filePathPlaceholder, filePath);
  }

  Future<Picture?> loadPicture(int id) async {
    final repo = createRepository<Picture>();
    final picture = await repo.getById(id);
    if (picture == null) {
      return picture;
    }
    picture.visitedAt = DateTime.now().toUtc();
    await repo.update(picture);
    return picture;
  }

  Future<Record?> loadRecord(int id) async {
    final repo = createRepository<Record>();
    final record = await repo.getById(id);
    if (record == null) {
      return record;
    }
    record.visitedAt = DateTime.now().toUtc();
    await repo.update(record);
    return record;
  }

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
    final recordData = record.toJson();
    final originalData = record.original?.toJson();
    final pictureData = record.picture?.toJson();
    final currentFilePath = filePath;

    final bytes = await Isolate.run(() {
      final archive = Archive();
      if (originalData != null) {
        for (final entry in _encodePicture(
          picture: Picture.fromJson(originalData),
          name: 'then',
          filePath: currentFilePath,
        )) {
          archive.add(entry);
        }
      }
      if (pictureData != null) {
        for (final entry in _encodePicture(
          picture: Picture.fromJson(pictureData),
          name: 'now',
          filePath: currentFilePath,
        )) {
          archive.add(entry);
        }
      }
      archive.add(ArchiveFile.string('meta.json', jsonEncode(recordData)));
      return ZipEncoder().encodeBytes(archive);
    });

    if (targetPath != null) {
      await File(targetPath).writeAsBytes(bytes);
    }
    return bytes;
  }

  Future<Uint8List?> exportMany({
    required List<Record> records,
    String? targetPath,
  }) async {
    if (records.isEmpty) return null;

    final recordsData = records.map((r) => r.toJson()).toList();
    final originalsData = records.map((r) => r.original?.toJson()).toList();
    final picturesData = records.map((r) => r.picture?.toJson()).toList();
    final currentFilePath = filePath;

    final bytes = await Isolate.run(() {
      final archive = Archive();
      for (var i = 0; i < recordsData.length; i++) {
        final dirName = Uuid().v4();
        archive.add(ArchiveFile.directory(dirName));
        if (originalsData[i] != null) {
          for (final entry in _encodePicture(
            picture: Picture.fromJson(originalsData[i]!),
            name: '$dirName/then',
            filePath: currentFilePath,
          )) {
            archive.add(entry);
          }
        }
        if (picturesData[i] != null) {
          for (final entry in _encodePicture(
            picture: Picture.fromJson(picturesData[i]!),
            name: '$dirName/now',
            filePath: currentFilePath,
          )) {
            archive.add(entry);
          }
        }
        archive.add(ArchiveFile.string('$dirName/meta.json', jsonEncode(recordsData[i])));
      }
      return ZipEncoder().encodeBytes(archive);
    });

    if (targetPath != null) {
      await File(targetPath).writeAsBytes(bytes);
    }
    return bytes;
  }

  Future<List<Record>> importFile({
    required XFile file,
  }) async {
    final fileBytes = await file.readAsBytes();

    final extracted = await Isolate.run(() => _extractRecords(fileBytes));

    if (extracted.isEmpty) return [];

    final records = <Record>[];
    for (final data in extracted) {
      final record = await _importRecord(data);
      if (record != null) {
        records.add(record);
      }
    }
    return records;
  }

  static List<Map<String, Object?>> _extractRecords(Uint8List fileBytes) {
    final archive = ZipDecoder().decodeBytes(fileBytes);

    Map<String, dynamic>? readJson(String name) {
      final file = archive.findFile(name);
      if (file == null) return null;
      final data = file.readBytes();
      if (data == null) return null;
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    }

    Uint8List? readImage(String name) {
      final file = archive.findFile(name);
      if (file == null) return null;
      final buffer = OutputMemoryStream();
      file.decompress(buffer);
      return Uint8List.fromList(buffer.getBytes());
    }

    final results = <Map<String, Object?>>[];

    final rootMeta = readJson('meta.json');
    if (rootMeta != null) {
      results.add({
        'record': rootMeta,
        'nowPicture': readJson('now.json'),
        'nowImage': readImage('now.jpg'),
        'thenPicture': readJson('then.json'),
        'thenImage': readImage('then.jpg'),
      });
      return results;
    }

    for (final entry in archive.files) {
      if (entry.isDirectory) {
        final prefix = '${entry.name}/';
        results.add({
          'record': readJson('${prefix}meta.json')!,
          'nowPicture': readJson('${prefix}now.json'),
          'nowImage': readImage('${prefix}now.jpg'),
          'thenPicture': readJson('${prefix}then.json'),
          'thenImage': readImage('${prefix}then.jpg'),
        });
      }
    }

    return results;
  }

  Future<Record?> _importRecord(Map<String, Object?> data) async {
    final recordJson = data['record'] as Map<String, dynamic>?;
    if (recordJson == null) return null;
    var record = Record.fromJson(recordJson);

    final nowPicture = await _upsertPicture(
      pictureJson: data['nowPicture'] as Map<String, dynamic>?,
      imageBytes: data['nowImage'] as Uint8List?,
    );
    if (nowPicture == null) return null;
    record.picture = nowPicture;
    record.pictureId = nowPicture.localId!;

    final thenPicture = await _upsertPicture(
      pictureJson: data['thenPicture'] as Map<String, dynamic>?,
      imageBytes: data['thenImage'] as Uint8List?,
    );
    record.original = thenPicture;
    record.originalId = thenPicture?.localId;

    record = await createRepository<Record>().upsert(record);
    return record;
  }

  Future<Picture?> _upsertPicture({
    required Map<String, dynamic>? pictureJson,
    required Uint8List? imageBytes,
  }) async {
    if (pictureJson == null) return null;
    final picture = Picture.fromJson(pictureJson);

    if (imageBytes != null) {
      final dirPath = filePath;
      if (dirPath == null || dirPath.isEmpty || kIsWeb) {
        picture.url = Uri.dataFromBytes(imageBytes, mimeType: 'image/jpg').toString();
      } else {
        final localPath = '$dirPath/pictures/${picture.id}.jpg';
        await File(localPath).writeAsBytes(imageBytes);
        picture.url = Uri.file('${DatabaseService.filePathPlaceholder}/pictures/${picture.id}.jpg').toString();
      }
    }

    return await createRepository<Picture>().upsert(picture);
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
    if (url != null && url.isScheme('file')) {

      await File(expandPath(url.path)).delete();
    }
    return true;
  }

  static List<ArchiveFile> _encodePicture({
    required Picture picture,
    required String name,
    required String? filePath,
  }) {
    final url = Uri.tryParse(picture.url);
    final mainFile = ArchiveFile.string('$name.json', jsonEncode(picture.toJson()));
    if (url == null) {
      return [mainFile];
    }
    if (url.isScheme('data')) {
      final attachment = UriData.fromUri(url).contentAsBytes();
      final size = attachment.lengthInBytes;
      final content = FileContentStream(InputMemoryStream(attachment));
      final attachmentFile = ArchiveFile.file('$name.jpg', size, content);
      return [mainFile, attachmentFile];
    }
    if (url.isScheme('file')) {
      final resolvedPath = _expandPath(url.path, filePath);
      final file = File(resolvedPath);
      final size = file.lengthSync();
      final content = FileContentStream(InputFileStream(resolvedPath));
      final attachmentFile = ArchiveFile.file('$name.jpg', size, content);
      return [mainFile, attachmentFile];
    }
    return [mainFile];
  }
}

