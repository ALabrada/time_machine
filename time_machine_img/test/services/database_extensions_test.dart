import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/services/database_service.dart';

Picture createPicture({
  required String id,
  String? url,
  String? provider,
  int? localId,
}) {
  return Picture(
    id: id,
    url: url ?? 'https://example.com/$id.jpg',
    latitude: 55.7558,
    longitude: 37.6173,
    provider: provider,
    localId: localId,
  );
}

Picture createDataUrlPicture({
  required String id,
  String? provider,
  int? localId,
}) {
  final imageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  return Picture(
    id: id,
    url: Uri.dataFromBytes(imageBytes, mimeType: 'image/jpg').toString(),
    latitude: 55.7558,
    longitude: 37.6173,
    provider: provider,
    localId: localId,
  );
}

void main() {
  group('DatabaseExtensions export', () {
    late Database db;
    late DatabaseService service;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_export_${DateTime.now().millisecondsSinceEpoch}.db');
      service = DatabaseService(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    group('export single record', () {
      test('produces valid zip with meta.json when no pictures', () async {
        final record = Record(
          pictureId: 1,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          visitedAt: DateTime(2024),
        );
        final repo = service.createRepository<Record>();
        await repo.insert(record);

        final bytes = await service.export(record: record);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        expect(archive.findFile('meta.json'), isNotNull);
        expect(archive.findFile('now.json'), isNull);
        expect(archive.findFile('then.json'), isNull);
      });

      test('includes now picture metadata', () async {
        final pic = createPicture(id: 'pic_now', localId: 10);
        final picRepo = service.createRepository<Picture>();
        await picRepo.insert(pic);

        final record = Record(
          pictureId: pic.localId!,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          picture: pic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final bytes = await service.export(record: record);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        final nowJson = archive.findFile('now.json');
        expect(nowJson, isNotNull);
        final decoded = jsonDecode(utf8.decode(nowJson!.readBytes()!));
        expect(decoded['id'], 'pic_now');
      });

      test('includes original and now picture metadata', () async {
        final original = createPicture(id: 'pic_original', localId: 20);
        final picture = createPicture(id: 'pic_now', localId: 30);
        final picRepo = service.createRepository<Picture>();
        await picRepo.insert(original);
        await picRepo.insert(picture);

        final record = Record(
          pictureId: picture.localId!,
          originalId: original.localId,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          original: original,
          picture: picture,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final bytes = await service.export(record: record);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        expect(archive.findFile('then.json'), isNotNull);
        expect(archive.findFile('now.json'), isNotNull);
        expect(archive.findFile('then.jpg'), isNull);
        expect(archive.findFile('now.jpg'), isNull);
      });

      test('embeds image data for data URL pictures', () async {
        final pic = createDataUrlPicture(id: 'pic_data', localId: 40);
        final picRepo = service.createRepository<Picture>();
        await picRepo.insert(pic);

        final record = Record(
          pictureId: pic.localId!,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          picture: pic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final bytes = await service.export(record: record);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        expect(archive.findFile('now.jpg'), isNotNull);
      });

      test('writes to targetPath when provided', () async {
        final record = Record(
          pictureId: 1,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
        );
        final repo = service.createRepository<Record>();
        await repo.insert(record);

        final dir = Directory.systemTemp.createTempSync('export_test_');
        final targetPath = '${dir.path}/export.zip';

        final bytes = await service.export(record: record, targetPath: targetPath);

        expect(bytes, isNotNull);
        expect(File(targetPath).existsSync(), isTrue);
        expect(File(targetPath).readAsBytesSync(), bytes);

        dir.deleteSync(recursive: true);
      });
    });

    group('exportMany', () {
      test('returns null for empty list', () async {
        final result = await service.exportMany(records: []);
        expect(result, isNull);
      });

      test('exports multiple records in separate directories', () async {
        final records = <Record>[];
        final recordRepo = service.createRepository<Record>();

        for (int i = 0; i < 3; i++) {
          final record = Record(
            pictureId: i + 1,
            createdAt: DateTime(2024, 1, i + 1),
            updateAt: DateTime(2024, 1, i + 1),
          );
          await recordRepo.insert(record);
          records.add(record);
        }

        final bytes = await service.exportMany(records: records);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        final dirs = archive.files.where((f) => f.isDirectory).toList();
        expect(dirs.length, 3);
        for (final dir in dirs) {
          final meta = archive.findFile('${dir.name}meta.json');
          expect(meta, isNotNull);
        }
      });

      test('includes picture data for each record', () async {
        final picRepo = service.createRepository<Picture>();
        final recordRepo = service.createRepository<Record>();
        final records = <Record>[];

        for (int i = 0; i < 2; i++) {
          final pic = createDataUrlPicture(id: 'pic_$i', localId: 100 + i);
          await picRepo.insert(pic);
          final record = Record(
            pictureId: pic.localId!,
            createdAt: DateTime(2024, 1, i + 1),
            updateAt: DateTime(2024, 1, i + 1),
            picture: pic,
          );
          await recordRepo.insert(record);
          records.add(record);
        }

        final bytes = await service.exportMany(records: records);

        expect(bytes, isNotNull);
        final archive = ZipDecoder().decodeBytes(bytes!);
        expect(archive.files.where((f) => f.name.endsWith('.jpg')).length, 2);
      });
    });
  });

  group('DatabaseExtensions import', () {
    late Database db;
    late DatabaseService service;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_import_${DateTime.now().millisecondsSinceEpoch}.db');
      service = DatabaseService(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    group('importFile', () {
      test('imports single record from manually constructed archive', () async {
        final archive = Archive();
        archive.add(ArchiveFile.string('meta.json', jsonEncode({
          'pictureId': 42,
          'createdAt': DateTime(2024).millisecondsSinceEpoch,
          'updateAt': DateTime(2024).millisecondsSinceEpoch,
        })));
        archive.add(ArchiveFile.string('now.json', jsonEncode({
          'id': 'imported_pic',
          'url': 'https://example.com/pic.jpg',
          'latitude': 10.0,
          'longitude': 20.0,
        })));
        final zipBytes = ZipEncoder().encodeBytes(archive);

        final xfile = XFile.fromData(zipBytes);
        final results = await service.importFile(file: xfile);

        expect(results.length, 1);
        expect(results[0].picture, isNotNull);
        expect(results[0].picture!.id, 'imported_pic');
      });

      test('imports roundtrip: export then import preserves picture id', () async {
        final pic = createPicture(id: 'roundtrip_pic', localId: 100);
        final picRepo = service.createRepository<Picture>();
        await picRepo.insert(pic);

        final record = Record(
          pictureId: pic.localId!,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          picture: pic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final exportBytes = await service.export(record: record);
        final xfile = XFile.fromData(exportBytes!);
        final results = await service.importFile(file: xfile);

        expect(results.length, 1);
        expect(results[0].picture, isNotNull);
        expect(results[0].picture!.id, 'roundtrip_pic');
      });

      test('imports roundtrip with embedded image stores as data URL', () async {
        final pic = createDataUrlPicture(id: 'data_img', localId: 60);
        final picRepo = service.createRepository<Picture>();
        await picRepo.insert(pic);

        final record = Record(
          pictureId: pic.localId!,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          picture: pic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final exportBytes = await service.export(record: record);
        final xfile = XFile.fromData(exportBytes!);
        final results = await service.importFile(file: xfile);

        expect(results.length, 1);
        expect(results[0].picture, isNotNull);
        expect(results[0].picture!.url.startsWith('data:'), isTrue);
      });

      test('imports roundtrip with original and picture', () async {
        final picRepo = service.createRepository<Picture>();
        final originalPic = createPicture(id: 'orig_pic', localId: 70);
        final nowPic = createPicture(id: 'now_pic', localId: 80);
        await picRepo.insert(originalPic);
        await picRepo.insert(nowPic);

        final record = Record(
          pictureId: nowPic.localId!,
          originalId: originalPic.localId,
          createdAt: DateTime(2024),
          updateAt: DateTime(2024),
          original: originalPic,
          picture: nowPic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(record);

        final exportBytes = await service.export(record: record);
        final xfile = XFile.fromData(exportBytes!);
        final results = await service.importFile(file: xfile);

        expect(results.length, 1);
        expect(results[0].picture!.id, 'now_pic');
        expect(results[0].original!.id, 'orig_pic');
      });

      test('full roundtrip: export then import and compare with original', () async {
        final picRepo = service.createRepository<Picture>();
        final origPic = createPicture(id: 'full_orig', localId: 90);
        final nowPic = createPicture(id: 'full_now', localId: 91);
        await picRepo.insert(origPic);
        await picRepo.insert(nowPic);

        final original = Record(
          pictureId: nowPic.localId!,
          originalId: origPic.localId,
          createdAt: DateTime(2024, 6, 15, 10, 30, 0),
          updateAt: DateTime(2024, 6, 15, 12, 0, 0),
          visitedAt: DateTime(2024, 6, 15, 14, 0, 0),
          height: 1080.0,
          width: 1920.0,
          originalViewPort: '0,0,800,600',
          pictureViewPort: '100,50,1920,1080',
          original: origPic,
          picture: nowPic,
        );
        final recordRepo = service.createRepository<Record>();
        await recordRepo.insert(original);

        final exportBytes = await service.export(record: original);
        expect(exportBytes, isNotNull);

        final xfile = XFile.fromData(exportBytes!);

        final db2 = await databaseFactoryMemory.openDatabase('test_import2_${DateTime.now().millisecondsSinceEpoch}.db');
        final importService = DatabaseService(db: db2);

        final results = await importService.importFile(file: xfile);

        expect(results.length, 1);
        final imported = results[0];

        expect(imported.pictureId, isNot(original.pictureId));
        expect(imported.picture, isNotNull);
        expect(imported.picture!.id, original.picture!.id);
        expect(imported.picture!.url, original.picture!.url);
        expect(imported.picture!.latitude, original.picture!.latitude);
        expect(imported.picture!.longitude, original.picture!.longitude);
        expect(imported.picture!.provider, original.picture!.provider);

        expect(imported.original, isNotNull);
        expect(imported.original!.id, original.original!.id);
        expect(imported.original!.url, original.original!.url);

        expect(imported.createdAt, original.createdAt);
        expect(imported.updateAt, original.updateAt);
        expect(imported.visitedAt, original.visitedAt);
        expect(imported.height, original.height);
        expect(imported.width, original.width);
        expect(imported.originalViewPort, original.originalViewPort);
        expect(imported.pictureViewPort, original.pictureViewPort);

        await db2.close();
      });

      test('imports multi-record archive with directories', () async {
        final archive = Archive();
        for (int i = 0; i < 2; i++) {
          final dirName = 'dir_$i';
          archive.add(ArchiveFile.directory(dirName));
          archive.add(ArchiveFile.string('$dirName/meta.json', jsonEncode({
            'pictureId': 200 + i,
            'createdAt': DateTime(2024, 1, i + 1).millisecondsSinceEpoch,
            'updateAt': DateTime(2024, 1, i + 1).millisecondsSinceEpoch,
          })));
          archive.add(ArchiveFile.string('$dirName/now.json', jsonEncode({
            'id': 'multi_pic_$i',
            'url': 'https://example.com/$i.jpg',
            'latitude': 10.0,
            'longitude': 20.0,
          })));
        }
        final zipBytes = ZipEncoder().encodeBytes(archive);
        final xfile = XFile.fromData(zipBytes);
        final results = await service.importFile(file: xfile);

        expect(results.length, 2);
        expect(results[0].picture, isNotNull);
        expect(results[1].picture, isNotNull);
        expect(results[0].picture!.id, 'multi_pic_0');
        expect(results[1].picture!.id, 'multi_pic_1');
      });
    });
  });
}
