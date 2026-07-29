import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:time_machine_db/time_machine_db.dart';
import 'mock_cloud_sync_provider.dart';

void main() {
  group('CloudSyncService', () {
    test('isActive returns false when no provider is set', () async {
      final db = await databaseFactoryMemory.openDatabase('test_no_provider.db');
      final localService = DatabaseService(db: db);
      final service = CloudSyncService(db: localService);

      expect(service.isActive, false);

      await service.dispose();
      await db.close();
    });

    test('isActive returns true after setProvider', () async {
      final db = await databaseFactoryMemory.openDatabase('test_active.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      expect(syncService.isActive, true);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud does nothing when local and cloud are empty', () async {
      final db = await databaseFactoryMemory.openDatabase('test_empty_sync.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      await syncService.syncWithCloud();

      final cloudRecords = await mockProvider.listRecords('records');
      expect(cloudRecords, isEmpty);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('push new local records to cloud via syncWithCloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_push_local.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();

      final pic = Picture(
        id: 'pic1',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
      );
      await pictureRepo.insert(pic);

      final now = DateTime.now();
      final record = Record(
        pictureId: pic.localId!,
        createdAt: now,
        updateAt: now,
      );
      await recordRepo.insert(record);

      await syncService.syncWithCloud();

      final cloudRecords = await mockProvider.listRecords('records');
      expect(cloudRecords, hasLength(1));
      expect(cloudRecords.first['pictureId'], isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pull cloud records to local via syncWithCloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pull_cloud.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final cloudData = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      };
      mockProvider.addRecord('records', 'cloud_record_1', cloudData);

      final records = await syncService.pullRecords();
      expect(records, hasLength(1));

      final localRepo = dbService.createRepository<Record>();
      final localRecords = await localRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.width, 200.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('_loadRecord: incoming newer than local overwrites local', () async {
      final db = await databaseFactoryMemory.openDatabase('test_newer_incoming.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final earlier = DateTime(2024, 1, 1);
      final later = DateTime(2024, 6, 1);

      final existing = Record(
        pictureId: 0,
        createdAt: earlier,
        updateAt: earlier,
      );
      await recordRepo.insert(existing);

      final incomingJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': earlier.millisecondsSinceEpoch,
        'updateAt': later.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 200.0,
        'width': 300.0,
        'cloudId': 'cloud_r1',
      };
      mockProvider.addRecord('records', 'cloud_r1', incomingJson);

      final pulled = await syncService.pullRecord('cloud_r1');
      expect(pulled, isNotNull);
      expect(pulled!.height, 200.0);

      final localCopy = await recordRepo.findRecordByCloudId('cloud_r1');
      expect(localCopy, isNotNull);
      expect(localCopy!.height, 200.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('_loadRecord: incoming older than local keeps local', () async {
      final db = await databaseFactoryMemory.openDatabase('test_older_incoming.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final earlier = DateTime(2024, 1, 1);
      final later = DateTime(2024, 6, 1);

      final existing = Record(
        pictureId: 0,
        createdAt: earlier,
        updateAt: later,
        height: 500.0,
        width: 600.0,
      );
      await recordRepo.insert(existing);
      existing.cloudId = 'cloud_r2';
      await recordRepo.update(existing);

      final incomingJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': earlier.millisecondsSinceEpoch,
        'updateAt': earlier.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
        'cloudId': 'cloud_r2',
      };
      mockProvider.addRecord('records', 'cloud_r2', incomingJson);

      final pulled = await syncService.pullRecord('cloud_r2');
      expect(pulled, isNotNull);
      expect(pulled!.height, 100.0);

      final localCopy = await recordRepo.findRecordByCloudId('cloud_r2');
      expect(localCopy, isNotNull);
      expect(localCopy!.height, 500.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pushRecord sets cloudId on local record', () async {
      final db = await databaseFactoryMemory.openDatabase('test_push_record_cloudid.db');
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
      );
      await recordRepo.insert(record);

      await syncService.pushRecord(record);

      expect(record.cloudId, isNotNull);

      final localCopy = await recordRepo.getById(record.localId!);
      expect(localCopy, isNotNull);
      expect(localCopy!.cloudId, record.cloudId);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pullRecords returns correct number of records', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pull_records_count.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      for (int i = 0; i < 3; i++) {
        final cloudData = <String, dynamic>{
          'pictureId': i,
          'originalId': null,
          'createdAt': now.millisecondsSinceEpoch,
          'updateAt': now.add(Duration(hours: i)).millisecondsSinceEpoch,
          'visitedAt': null,
          'height': 100.0 + i,
          'width': 200.0 + i,
          'cloudId': 'cr_$i',
        };
        mockProvider.addRecord('records', 'cr_$i', cloudData);
      }

      final records = await syncService.pullRecords();
      expect(records, hasLength(3));

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pullRecords respects since filter', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pull_since.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      for (int i = 0; i < 3; i++) {
        final cloudData = <String, dynamic>{
          'pictureId': i,
          'originalId': null,
          'createdAt': now.millisecondsSinceEpoch,
          'updateAt': now.add(Duration(hours: i)).millisecondsSinceEpoch,
          'visitedAt': null,
          'height': 100.0 + i,
          'width': 200.0 + i,
          'cloudId': 'cr_since_$i',
        };
        mockProvider.addRecord('records', 'cr_since_$i', cloudData);
      }

      final since = now.add(const Duration(hours: 1));
      final records = await syncService.pullRecords(since: since);
      expect(records, hasLength(1));

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('deleteRecord deletes from cloud and cloud picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_delete_record.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final picture = Picture(
        id: 'del_pic',
        url: 'https://example.com/del.jpg',
        latitude: 10.0,
        longitude: 20.0,
        cloudId: 'cloud_del_pic',
      );
      mockProvider.addRecord('pictures', 'cloud_del_pic', picture.toJson());

      final now = DateTime.now();
      final record = Record(
        pictureId: 1,
        createdAt: now,
        updateAt: now,
        cloudId: 'cloud_del_rec',
        picture: picture,
      );
      mockProvider.addRecord('records', 'cloud_del_rec', record.toJson());

      await syncService.deleteRecordFromCould(record);

      expect(mockProvider.hasRecord('records', 'cloud_del_rec'), false);
      expect(mockProvider.hasRecord('pictures', 'cloud_del_pic'), false);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud pushes simple local record without picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_sync_push_simple.db');
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
      );
      await recordRepo.insert(record);

      await syncService.syncWithCloud();

      // syncWithCloud creates new Record objects from the DB, so check the DB
      final localRecords = await recordRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.cloudId, isNotNull);

      expect(mockProvider.hasRecord('records', localRecords.first.cloudId!), true);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud syncs local updates to existing cloud records', () async {
      final db = await databaseFactoryMemory.openDatabase('test_sync_update.db');
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
        cloudId: 'existing_cloud_rec',
        height: 100,
        width: 200,
      );
      await recordRepo.insert(record);

      final cloudJson = record.toJson();
      mockProvider.addRecord('records', 'existing_cloud_rec', cloudJson);

      record.height = 999;
      record.updateAt = now.add(const Duration(hours: 1));
      await recordRepo.update(record);

      await syncService.syncWithCloud();

      final cloudData = mockProvider.getRecordData('records', 'existing_cloud_rec');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 999);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('event processing: EntityInserted triggers pushRecord', () async {
      final db = await databaseFactoryMemory.openDatabase('test_event_push.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Picture: 'pictures', Record: 'records'},
        supportsEvents: true,
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
      );
      final recordRepo = dbService.createRepository<Record>();
      await recordRepo.insert(record);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(record.cloudId, isNotNull);
      expect(mockProvider.hasRecord('records', record.cloudId!), true);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud with conflicting records pushes local when newer', () async {
      final db = await databaseFactoryMemory.openDatabase('test_conflict.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final older = now.subtract(const Duration(days: 1));

      final localRecord = Record(
        pictureId: 0,
        createdAt: older,
        updateAt: now,
        cloudId: 'conflict_rec',
        height: 777,
        width: 888,
      );
      await recordRepo.insert(localRecord);

      final cloudJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': older.millisecondsSinceEpoch,
        'updateAt': older.millisecondsSinceEpoch,
        'height': 100.0,
        'width': 200.0,
      };
      mockProvider.addRecord('records', 'conflict_rec', cloudJson);

      await syncService.syncWithCloud();

      final cloudData = mockProvider.getRecordData('records', 'conflict_rec');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 777);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud keeps cloud when cloud is newer', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_newer.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final older = now.subtract(const Duration(days: 1));

      final localRecord = Record(
        pictureId: 0,
        createdAt: older,
        updateAt: older,
        cloudId: 'cloud_newer_rec',
        height: 777,
        width: 888,
      );
      await recordRepo.insert(localRecord);

      final cloudJson = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': older.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'height': 100.0,
        'width': 200.0,
      };
      mockProvider.addRecord('records', 'cloud_newer_rec', cloudJson);

      await syncService.syncWithCloud();

      // Cloud is newer, so local should NOT overwrite cloud
      final cloudData = mockProvider.getRecordData('records', 'cloud_newer_rec');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 100.0);

      // Local should be updated with cloud values
      final localCopy = await recordRepo.findRecordByCloudId('cloud_newer_rec');
      expect(localCopy, isNotNull);
      expect(localCopy!.height, 100.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudInsertedEvent pulls cloud record to local', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_inserted.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        supportsEvents: true,
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final cloudData = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 150.0,
        'width': 250.0,
      };
      mockProvider.addRecord('records', 'cloud_ins_1', cloudData);
      mockProvider.emitChange(CloudInsertedEvent(id: 'cloud_ins_1', collection: 'records'));

      await Future.delayed(const Duration(milliseconds: 100));

      final localRepo = dbService.createRepository<Record>();
      final localRecords = await localRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.width, 250.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudUpdatedEvent updates local record with newer cloud data', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_updated.db');
      final recordStore = intMapStoreFactory.store('record');
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;

      await recordStore.add(db, {
        'pictureId': 0,
        'createdAt': ts,
        'updateAt': ts,
        'height': 10.0,
        'width': 20.0,
        'cloudId': 'cloud_upd_1',
      });

      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        supportsEvents: true,
      );
      mockProvider.addRecord('records', 'cloud_upd_1', {
        'pictureId': 0,
        'originalId': null,
        'createdAt': ts,
        'updateAt': ts,
        'visitedAt': null,
        'height': 10.0,
        'width': 20.0,
      });

      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final laterTs = now.add(const Duration(hours: 2)).millisecondsSinceEpoch;
      mockProvider.addRecord('records', 'cloud_upd_1', {
        'pictureId': 0,
        'originalId': null,
        'createdAt': ts,
        'updateAt': laterTs,
        'visitedAt': null,
        'height': 99.0,
        'width': 199.0,
      });
      mockProvider.emitChange(CloudUpdatedEvent(id: 'cloud_upd_1', collection: 'records'));

      await Future.delayed(const Duration(milliseconds: 200));

      final recordRepo = dbService.createRepository<Record>();
      final updated = await recordRepo.findRecordByCloudId('cloud_upd_1');
      expect(updated, isNotNull);
      expect(updated!.height, 99.0);
      expect(updated.width, 199.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudDeletedEvent removes local record and picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_deleted.db');
      final pictureStore = intMapStoreFactory.store('picture');
      final recordStore = intMapStoreFactory.store('record');
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;

      final picKey = await pictureStore.add(db, {
        'id': 'del_evt_pic',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 1.0,
        'longitude': 2.0,
      });
      await recordStore.add(db, {
        'pictureId': picKey,
        'createdAt': ts,
        'updateAt': ts,
        'height': 10.0,
        'width': 20.0,
        'cloudId': 'cloud_del_1',
      });

      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        supportsEvents: true,
      );
      mockProvider.addRecord('records', 'cloud_del_1', {
        'pictureId': 0,
        'originalId': null,
        'createdAt': ts,
        'updateAt': ts,
        'visitedAt': null,
        'height': 10.0,
        'width': 20.0,
      });

      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      mockProvider.emitChange(CloudDeletedEvent(id: 'cloud_del_1', collection: 'records'));

      await Future.delayed(const Duration(milliseconds: 200));

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();
      expect(await recordRepo.findRecordByCloudId('cloud_del_1'), isNull);
      final deletedPic = await pictureRepo.getById(picKey);
      expect(deletedPic, isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudReconnectedEvent triggers full sync', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_reconnected.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        supportsEvents: true,
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final cloudData = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 300.0,
        'width': 400.0,
      };
      mockProvider.addRecord('records', 'cloud_rec_1', cloudData);
      mockProvider.emitChange(const CloudReconnectedEvent());

      await Future.delayed(const Duration(milliseconds: 100));

      final localRepo = dbService.createRepository<Record>();
      final localRecords = await localRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.width, 400.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('UnknownEvent triggers full sync', () async {
      final db = await databaseFactoryMemory.openDatabase('test_unknown_event.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        supportsEvents: true,
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final cloudData = <String, dynamic>{
        'pictureId': 0,
        'originalId': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updateAt': now.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 50.0,
        'width': 60.0,
      };
      mockProvider.addRecord('records', 'cloud_unk_1', cloudData);
      mockProvider.emitChange();

      await Future.delayed(const Duration(milliseconds: 100));

      final localRepo = dbService.createRepository<Record>();
      final localRecords = await localRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.width, 60.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('EntityUpdated event triggers pushRecord to update cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_entity_updated.db');
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
        height: 100,
        width: 200,
      );
      await recordRepo.insert(record);
      await syncService.pushRecord(record);
      final cloudId = record.cloudId!;

      record.height = 999;
      record.updateAt = now.add(const Duration(hours: 1));
      await recordRepo.update(record);

      await Future.delayed(const Duration(milliseconds: 100));

      final cloudData = mockProvider.getRecordData('records', cloudId);
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 999);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('EntityRemoved event removes record from cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_entity_removed.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
        cloudId: 'cloud_del_evt',
      );
      final recordRepo = dbService.createRepository<Record>();
      await recordRepo.insert(record);
      mockProvider.addRecord('records', 'cloud_del_evt', record.toJson());
      expect(mockProvider.hasRecord('records', 'cloud_del_evt'), true);

      await Future.delayed(const Duration(milliseconds: 50));

      await recordRepo.delete(record.localId!);

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockProvider.hasRecord('records', 'cloud_del_evt'), false);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('changing provider invalidates old cloudId and re-pushes record to new provider', () async {
      final db = await databaseFactoryMemory.openDatabase('test_provider_change.db');
      final dbService = DatabaseService(db: db);

      final providerA = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'prov_a/',
      );
      final syncService = CloudSyncService(db: dbService);
      await syncService.setProvider(providerA);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
      );
      await recordRepo.insert(record);
      await syncService.syncWithCloud();

      await Future.delayed(const Duration(milliseconds: 200));

      final localA = await recordRepo.list();
      expect(localA, hasLength(1));
      expect(localA.first.cloudId, startsWith('prov_a/'));
      final oldStripped = localA.first.cloudId!.substring('prov_a/'.length);
      expect(providerA.hasRecord('records', oldStripped), true);

      final providerB = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'prov_b/',
      );
      await syncService.setProvider(providerB);

      await Future.delayed(const Duration(milliseconds: 200));

      final localB = await recordRepo.list();
      expect(localB, hasLength(1));
      expect(localB.first.cloudId, startsWith('prov_b/'));
      expect(providerA.hasRecord('records', oldStripped), true);

      final newStripped = localB.first.cloudId!.substring('prov_b/'.length);
      expect(providerB.hasRecord('records', newStripped), true);

      await syncService.dispose();
      providerA.dispose();
      providerB.dispose();
      await db.close();
    });
  });
}
