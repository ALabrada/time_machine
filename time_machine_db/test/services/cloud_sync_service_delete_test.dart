import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:time_machine_db/time_machine_db.dart';
import 'mock_cloud_sync_provider.dart';

Future<Picture> insertPicture(
  DatabaseService dbService, {
  required String id,
  required String provider,
}) async {
  final picture = Picture(
    id: id,
    provider: provider,
    url: 'data:image/jpg;base64,AA==',
    latitude: 48.0,
    longitude: 2.0,
  );
  return await dbService.createRepository<Picture>().insert(picture);
}

Future<Record> insertRecord(
  DatabaseService dbService,
  Picture picture, {
  DateTime? updateAt,
}) async {
  final time = updateAt ?? DateTime.now();
  final record = Record(
    pictureId: picture.localId!,
    createdAt: time,
    updateAt: time,
  );
  return await dbService.createRepository<Record>().insert(record);
}

Map<String, dynamic> cloudPictureJson({
  required String id,
  required String provider,
}) => {
  'id': id,
  'provider': provider,
  'url': 'data:image/jpg;base64,AA==',
  'latitude': 48.0,
  'longitude': 2.0,
};

Map<String, dynamic> cloudRecordJson({
  required String pictureKey,
  required DateTime updateAt,
  DateTime? createdAt,
  DateTime? deletedAt,
}) => {
  'pictureId': pictureKey,
  'originalId': null,
  'createdAt': (createdAt ?? updateAt).millisecondsSinceEpoch,
  'updateAt': updateAt.millisecondsSinceEpoch,
  'visitedAt': null,
  'height': 100.0,
  'width': 200.0,
  if (deletedAt != null) 'deletedAt': deletedAt.millisecondsSinceEpoch,
};

void main() {
  group('CloudSyncService delete behavior', () {
    test('offline delete of a synced record keeps tombstone mirrors and deletes from cloud on reconnect', () async {
      final db = await databaseFactoryMemory.openDatabase('test_offline_delete.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = await insertPicture(dbService, id: 'od1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);
      record.picture = picture;
      await syncService.records!.pushRecord(record);

      expect(mockProvider.hasRecord('records', 'pastvu/od1'), true);
      expect(mockProvider.hasRecord('pictures', 'pastvu/od1'), true);

      await syncService.setProvider(null);

      final recordRepo = dbService.createRepository<Record>();
      final recordCopy = (await recordRepo.getById(record.localId!))!;
      await syncService.deleteRecord(recordCopy);
      await recordRepo.delete(recordCopy.localId!);

      final recordMirror = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(recordMirror, isNotNull);
      expect(recordMirror!.deletedAt, isNotNull);

      final pictureMirror = await dbService.createRepository<PictureMirror>()
          .findByPictureAndCloud(picture.localId!, 'mock');
      expect(pictureMirror, isNotNull);
      expect(pictureMirror!.deletedAt, isNotNull);

      expect(await recordRepo.getById(record.localId!), isNull);
      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNotNull);

      expect(mockProvider.hasRecord('records', 'pastvu/od1'), true);

      await syncService.setProvider(mockProvider);

      expect(mockProvider.hasRecord('records', 'pastvu/od1'), false);
      expect(mockProvider.hasRecord('pictures', 'pastvu/od1'), false);
      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('online delete sets deletedAt in cloud and removes local record', () async {
      final db = await databaseFactoryMemory.openDatabase('test_online_delete.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = await insertPicture(dbService, id: 'od1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);
      record.picture = picture;
      await syncService.records!.pushRecord(record);

      expect(mockProvider.hasRecord('records', 'pastvu/od1'), true);
      expect(mockProvider.hasRecord('pictures', 'pastvu/od1'), true);

      await dbService.createRepository<Record>().delete(record.localId!);

      await Future.delayed(const Duration(milliseconds: 300));

      final cloudMetadata = mockProvider.getMetadata('records', 'pastvu/od1');
      expect(cloudMetadata, isNotNull);
      expect(cloudMetadata!.deletedAt, isNotNull);
      expect(mockProvider.hasRecord('records', 'pastvu/od1'), false);
      expect(mockProvider.hasRecord('pictures', 'pastvu/od1'), false);

      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull);
      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);

      final mirror = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(mirror, isNotNull);
      expect(mirror!.deletedAt, isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('sync deletes local record when cloud record has deletedAt', () async {
      final db = await databaseFactoryMemory.openDatabase('test_sync_delete_local.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
      );

      final now = DateTime.now();
      final earlier = now.subtract(const Duration(days: 2));
      final deletedAt = now.subtract(const Duration(days: 1));

      final picture = await insertPicture(dbService, id: 'sd1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: earlier);

      await dbService.createRepository<RecordMirror>().insert(RecordMirror(
        id: 'pastvu/sd1',
        recordId: record.localId!,
        createdAt: earlier,
        updatedAt: earlier,
        cloudId: 'mock',
      ));
      await dbService.createRepository<PictureMirror>().insert(PictureMirror(
        id: 'pastvu/sd1',
        pictureId: picture.localId!,
        createdAt: earlier,
        updatedAt: earlier,
        cloudId: 'mock',
      ));

      mockProvider.addRecord('pictures', 'pastvu/sd1', {
        ...cloudPictureJson(id: 'sd1', provider: 'pastvu'),
        'deletedAt': deletedAt.millisecondsSinceEpoch,
      });
      mockProvider.addRecord('records', 'pastvu/sd1', cloudRecordJson(
        pictureKey: 'pastvu/sd1',
        updateAt: earlier,
        deletedAt: deletedAt,
      ));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      expect(await dbService.createRepository<Record>().list(), isEmpty);
      expect(await dbService.createRepository<Picture>().list(), isEmpty);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('first sync does not import deleted cloud records to local DB', () async {
      final db = await databaseFactoryMemory.openDatabase('test_first_sync_deleted.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
      );

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/fd1', {
        ...cloudPictureJson(id: 'fd1', provider: 'pastvu'),
        'deletedAt': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      });
      mockProvider.addRecord('records', 'pastvu/fd1', cloudRecordJson(
        pictureKey: 'pastvu/fd1',
        updateAt: now.subtract(const Duration(days: 2)),
        deletedAt: now.subtract(const Duration(days: 1)),
      ));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      expect(await recordRepo.list(), isEmpty);
      expect(await dbService.createRepository<Picture>().list(), isEmpty);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });
  });
}
