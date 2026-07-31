import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:time_machine_db/time_machine_db.dart';
import 'mock_cloud_sync_provider.dart';

void main() {
  group('CloudSyncService delete behavior', () {
    test('offline delete of synced record sets deletedAt instead of removing it', () async {
      final db = await databaseFactoryMemory.openDatabase('test_offline_delete.db');
      final dbService = DatabaseService(db: db);
      final syncService = CloudSyncService(db: dbService);

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();
      final now = DateTime.now();
      final picture = await pictureRepo.insert(Picture(
        id: 'od1',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
      ));
      final record = await recordRepo.insert(Record(
        pictureId: picture.localId!,
        createdAt: now,
        updateAt: now,
        cloudId: 'mock',
      ));
      final oldLocalId = record.localId!;

      await recordRepo.delete(oldLocalId);

      await Future.delayed(const Duration(milliseconds: 200));

      final localRecords = await recordRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.cloudId, 'mock');
      expect(localRecords.first.deletedAt, isNotNull);
      expect(localRecords.first.localId, isNot(oldLocalId));

      await syncService.dispose();
      await db.close();
    });

    test('online delete sets deletedAt in cloud and removes local record', () async {
      final db = await databaseFactoryMemory.openDatabase('test_online_delete.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();
      final now = DateTime.now();
      final picture = await pictureRepo.insert(Picture(
        id: 'od1',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
        cloudId: 'mock',
      ));
      final record = await recordRepo.insert(Record(
        pictureId: picture.localId!,
        createdAt: now,
        updateAt: now,
        cloudId: 'mock',
      ));

      mockProvider.addRecord('pictures', 'pastvu/od1', {
        'id': 'od1',
        'provider': 'pastvu',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 48.0,
        'longitude': 2.0,
      });
      mockProvider.addRecord('records', 'pastvu/od1', {
        'pictureId': 'pastvu/od1',
        'originalId': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      });
      expect(mockProvider.hasRecord('records', 'pastvu/od1'), true);

      await recordRepo.delete(record.localId!);

      await Future.delayed(const Duration(milliseconds: 200));

      final cloudData = mockProvider.getRecordData('records', 'pastvu/od1');
      expect(cloudData, isNotNull);
      expect(cloudData!['deletedAt'], isNotNull);

      final local = await recordRepo.findRecordByPictureId(picture.localId!);
      expect(local, isNull);

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

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();
      final now = DateTime.now();
      final earlier = now.subtract(const Duration(days: 2));
      final deletedAt = now.subtract(const Duration(days: 1));

      final picture = await pictureRepo.insert(Picture(
        id: 'sd1',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
      ));
      final record = Record(
        pictureId: picture.localId!,
        createdAt: earlier,
        updateAt: earlier,
        cloudId: 'mock',
        height: 100,
        width: 200,
      );
      await recordRepo.insert(record);
      expect(await recordRepo.list(), hasLength(1));

      mockProvider.addRecord('pictures', 'pastvu/sd1', {
        'id': 'sd1',
        'provider': 'pastvu',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 48.0,
        'longitude': 2.0,
      });
      mockProvider.addRecord('records', 'pastvu/sd1', {
        'pictureId': 'pastvu/sd1',
        'originalId': null,
        'createdAt': earlier.millisecondsSinceEpoch,
        'updateAt': earlier.millisecondsSinceEpoch,
        'deletedAt': deletedAt.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      });

      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      expect(await recordRepo.list(), isEmpty);

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
        'id': 'fd1',
        'provider': 'pastvu',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 48.0,
        'longitude': 2.0,
      });
      mockProvider.addRecord('records', 'pastvu/fd1', {
        'pictureId': 'pastvu/fd1',
        'originalId': null,
        'createdAt': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'updateAt': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'deletedAt': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      });

      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      expect(await recordRepo.list(), isEmpty);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });
  });
}
