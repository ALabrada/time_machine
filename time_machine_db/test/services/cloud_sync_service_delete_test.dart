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
      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
        cloudId: 'cloud_offline',
      );
      await recordRepo.insert(record);
      final oldLocalId = record.localId!;

      await recordRepo.delete(oldLocalId);

      await Future.delayed(const Duration(milliseconds: 200));

      final localRecords = await recordRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.cloudId, 'cloud_offline');
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
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
        cloudId: 'cloud_online',
      );
      mockProvider.addRecord('records', 'cloud_online', record.toJson());
      await recordRepo.insert(record);

      await recordRepo.delete(record.localId!);

      await Future.delayed(const Duration(milliseconds: 200));

      final cloudData = mockProvider.getRecordData('records', 'cloud_online');
      expect(cloudData, isNotNull);
      expect(cloudData!['deletedAt'], isNotNull);

      final local = await recordRepo.findRecordByCloudId('cloud_online');
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
      );

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final earlier = now.subtract(const Duration(days: 1));
      final deletedAt = now.subtract(const Duration(hours: 1));

      final record = Record(
        pictureId: 0,
        createdAt: earlier,
        updateAt: earlier,
        cloudId: 'cloud_del_sync',
        height: 100,
        width: 200,
      );
      await recordRepo.insert(record);
      expect(await recordRepo.list(), hasLength(1));

      final cloudJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': earlier.millisecondsSinceEpoch,
        'updateAt': earlier.millisecondsSinceEpoch,
        'deletedAt': deletedAt.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      };
      mockProvider.addRecord('records', 'cloud_del_sync', cloudJson);

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
      );

      final now = DateTime.now();
      final cloudJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'updateAt': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'deletedAt': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      };
      mockProvider.addRecord('records', 'cloud_del_first', cloudJson);

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
