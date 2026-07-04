import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file/file.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class _MockCacheManager implements BaseCacheManager {
  @override
  Future<fs.File> getSingleFile(String url,
      {String? key, Map<String, String>? headers}) {
    throw UnimplementedError('getSingleFile should not be called in these tests');
  }

  @override
  Stream<FileInfo> getFile(String url,
      {String? key, Map<String, String>? headers}) {
    throw UnimplementedError('getFile should not be called in these tests');
  }

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    throw UnimplementedError('getFileStream should not be called in these tests');
  }

  @override
  Future<FileInfo> downloadFile(String url,
      {String? key, Map<String, String>? authHeaders, bool force = false}) {
    throw UnimplementedError('downloadFile should not be called in these tests');
  }

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) {
    return Future.value(null);
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) {
    return Future.value(null);
  }

  @override
  Future<fs.File> putFile(String url, Uint8List fileBytes,
      {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) {
    throw UnimplementedError('putFile should not be called in these tests');
  }

  @override
  Future<fs.File> putFileStream(String url, Stream<List<int>> source,
      {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) {
    throw UnimplementedError('putFileStream should not be called in these tests');
  }

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  Future<void> dispose() async {}
}

Position _makePosition({
  double latitude = 0,
  double longitude = 0,
  double altitude = 0,
  double heading = 0,
  double accuracy = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.timestamp(),
    accuracy: accuracy,
    altitude: altitude,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseService databaseService;
  late Uint8List testImageBytes;
  late XFile testXFile;
  late CacheService cacheService;

  setUp(() async {
    final image = img.Image(width: 4, height: 4);
    for (int y = 0; y < 4; y++) {
      for (int x = 0; x < 4; x++) {
        image.setPixelRgba(x, y, 255, 128, 64, 255);
      }
    }
    testImageBytes = Uint8List.fromList(img.encodeJpg(image));
    testXFile = XFile.fromData(testImageBytes, name: 'test.jpg');

    db = await databaseFactoryMemory.openDatabase(
      'test_cam_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    databaseService = DatabaseService(db: db);
    cacheService = CacheService(cacheManager: _MockCacheManager());
  });

  tearDown(() async {
    await db.close();
  });

  group('CamDatabaseService', () {
    group('createRecord', () {
      test('creates record with data URI when filePath is null', () async {
        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
        );

        expect(record.localId, greaterThan(0));
        expect(record.pictureId, greaterThan(0));
        expect(record.picture, isNotNull);
        expect(record.picture!.url, startsWith('data:'));
        expect(record.width, isNull);
        expect(record.height, isNull);
        expect(record.pictureViewPort, isNull);
        expect(record.originalViewPort, isNull);
        expect(record.originalId, isNull);
        expect(record.original, isNull);

        final repo = Repository<Picture>.create(db: db);
        final savedPicture = await repo.getById(record.pictureId);
        expect(savedPicture, isNotNull);
        expect(savedPicture!.url, startsWith('data:'));
        expect(savedPicture.provider, '');
      });

      test('creates record with pictureViewPort when height and width are given',
          () async {
        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          height: 200,
          width: 400,
        );

        expect(record.height, 200);
        expect(record.width, 400);
        expect(record.pictureViewPort, isNotNull);
        expect(record.originalViewPort, isNull);

        final parts = record.pictureViewPort!.split(',');
        expect(parts.length, 4);
        for (final p in parts) {
          expect(double.tryParse(p), isNotNull);
        }
      });

      test('does not calculate viewPort when height or width is null', () async {
        var record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          height: 200,
        );
        expect(record.pictureViewPort, isNull);

        record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          width: 400,
        );
        expect(record.pictureViewPort, isNull);
      });

      test('creates record with position coordinates', () async {
        final position = _makePosition(latitude: 48.8566, longitude: 2.3522);

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          position: position,
        );

        expect(record.picture!.latitude, closeTo(48.8566, 0.0001));
        expect(record.picture!.longitude, closeTo(2.3522, 0.0001));
        expect(record.picture!.altitude, isZero);
        expect(record.picture!.bearing, isZero);
      });

      test('creates record with altitude and address', () async {
        final position = _makePosition(
          latitude: 40.7128,
          longitude: -74.0060,
          altitude: 50.5,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          position: position,
          address: 'New York, USA',
        );

        expect(record.picture!.altitude, 50.5);
        expect(record.picture!.description, 'New York, USA');
      });

      test('sets coordinates from original when position is null', () async {
        final original = Picture(
          id: 'orig_coords',
          url: 'https://example.com/original.jpg',
          latitude: 51.5074,
          longitude: -0.1278,
          altitude: 100,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          original: original,
        );

        expect(record.picture!.latitude, closeTo(51.5074, 0.0001));
        expect(record.picture!.longitude, closeTo(-0.1278, 0.0001));
        expect(record.picture!.altitude, 100);
      });

      test('uses explicit heading over position heading and original bearing',
          () async {
        final position = _makePosition(
          latitude: 10,
          longitude: 20,
          heading: 90,
        );
        final original = Picture(
          id: 'orig_heading',
          url: 'https://example.com/orig.jpg',
          latitude: 0,
          longitude: 0,
          bearing: 270,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          heading: 180,
          position: position,
          original: original,
        );

        expect(record.picture!.bearing, 180);
      });

      test('uses position heading when heading is null', () async {
        final position = _makePosition(
          latitude: 48.8566,
          longitude: 2.3522,
          heading: 90,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          position: position,
        );

        expect(record.picture!.bearing, 90);
      });

      test('uses original bearing when heading and position heading are null',
          () async {
        final original = Picture(
          id: 'orig_bearing',
          url: 'https://example.com/orig.jpg',
          latitude: 0,
          longitude: 0,
          bearing: 270,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          original: original,
        );

        expect(record.picture!.bearing, 270);
      });

      test('sets time from createdAt parameter', () async {
        final createdAt = DateTime(2025, 3, 15, 10, 30, 45);

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          createdAt: createdAt,
        );

        expect(record.picture!.time, '2025-03-15');
        expect(record.createdAt, createdAt);
        expect(record.updateAt, createdAt);
      });

      test('persists picture and record in database', () async {
        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          address: 'Persist test',
        );

        final pictureRepo = Repository<Picture>.create(db: db);
        final savedPicture = await pictureRepo.getById(record.pictureId);
        expect(savedPicture, isNotNull);
        expect(savedPicture!.description, 'Persist test');

        final recordRepo = Repository<Record>.create(db: db);
        final savedRecord = await recordRepo.getById(record.localId!);
        expect(savedRecord, isNotNull);
        expect(savedRecord!.pictureId, record.pictureId);
      });

      test('uses file basename as id when file is within dirPath', () async {
        final dbPath = '/tmp/test_cam_db/${DateTime.now().millisecondsSinceEpoch}';
        final fileDir = databaseService.filePath ??
            '$dbPath/files';
        final filePath = '$fileDir/within_test.jpg';
        final file = File(filePath);
        await file.create(recursive: true);
        await file.writeAsBytes(testImageBytes);

        final localDb = await databaseFactoryMemory.openDatabase(
          'test_within_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        final localService = DatabaseService(db: localDb, dataPath: dbPath);
        final withinFile = XFile(filePath);

        try {
          final record = await localService.createRecord(
            file: withinFile,
            cacheService: cacheService,
          );

          expect(record.picture!.id, 'within_test.jpg');
          expect(record.picture!.url, contains('within_test.jpg'));
        } finally {
          await localDb.close();
          await file.delete();
        }
      });

      test('calculates originalViewPort when original and dimensions are given',
          () async {
        final imageData = base64Encode(testImageBytes);
        final dataUri = 'data:image/jpg;base64,$imageData';

        final original = Picture(
          id: 'orig_viewport',
          url: dataUri,
          latitude: 0,
          longitude: 0,
        );

        final record = await databaseService.createRecord(
          file: testXFile,
          cacheService: cacheService,
          original: original,
          height: 300,
          width: 600,
        );

        expect(record.pictureViewPort, isNotNull);
        expect(record.originalViewPort, isNotNull);
        expect(record.originalId, original.localId);
        expect(record.original, isNotNull);
      });
    });

    group('loadPicture', () {
      test('loads picture and updates visitedAt', () async {
        final repo = Repository<Picture>.create(db: db);
        final picture = Picture(
          id: 'load_test_1',
          url: 'https://example.com/pic1.jpg',
          latitude: 55.7558,
          longitude: 37.6173,
        );
        final inserted = await repo.insert(picture);

        final loaded = await databaseService.loadPicture(inserted.localId!);

        expect(loaded, isNotNull);
        expect(loaded!.id, 'load_test_1');
        expect(loaded.visitedAt, isNotNull);

        final diff = DateTime.now().toUtc().difference(loaded.visitedAt!);
        expect(diff.inSeconds, lessThan(2));

        final retrieved = await repo.getById(inserted.localId!);
        expect(retrieved!.visitedAt, isNotNull);
      });

      test('returns null for non-existent id', () async {
        final result = await databaseService.loadPicture(99999);
        expect(result, isNull);
      });
    });

    group('savePicture', () {
      test('inserts new picture without localId', () async {
        final picture = Picture(
          id: 'save_new',
          url: 'https://example.com/new.jpg',
          latitude: 10.0,
          longitude: 20.0,
        );

        final saved = await databaseService.savePicture(picture);

        expect(saved.localId, isNotNull);
        expect(saved.localId, greaterThan(0));

        final repo = Repository<Picture>.create(db: db);
        final retrieved = await repo.getById(saved.localId!);
        expect(retrieved, isNotNull);
        expect(retrieved!.id, 'save_new');
      });

      test('updates existing picture with localId', () async {
        final repo = Repository<Picture>.create(db: db);
        final picture = Picture(
          id: 'save_update',
          url: 'https://example.com/update.jpg',
          latitude: 30.0,
          longitude: 40.0,
        );
        final inserted = await repo.insert(picture);
        inserted.description = 'Updated description';

        final saved = await databaseService.savePicture(inserted);

        expect(saved.localId, inserted.localId);

        final retrieved = await repo.getById(inserted.localId!);
        expect(retrieved!.description, 'Updated description');
      });
    });
  });
}
