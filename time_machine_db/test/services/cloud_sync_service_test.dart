import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:time_machine_db/time_machine_db.dart';
import 'mock_cloud_sync_provider.dart';

Future<Picture> insertPicture(
  DatabaseService dbService, {
  required String id,
  required String provider,
  double latitude = 48.0,
  double longitude = 2.0,
}) async {
  final picture = Picture(
    id: id,
    provider: provider,
    url: 'data:image/jpg;base64,AA==',
    latitude: latitude,
    longitude: longitude,
  );
  return await dbService.createRepository<Picture>().insert(picture);
}

Future<Record> insertRecord(
  DatabaseService dbService,
  Picture picture, {
  DateTime? updateAt,
  double height = 100,
  double width = 200,
}) async {
  final time = updateAt ?? DateTime.now();
  final record = Record(
    pictureId: picture.localId!,
    createdAt: time,
    updateAt: time,
    height: height,
    width: width,
  );
  return await dbService.createRepository<Record>().insert(record);
}

Map<String, dynamic> cloudPictureJson({
  required String id,
  required String provider,
  String? url,
}) => {
  'id': id,
  'provider': provider,
  'url': url ?? 'data:image/jpg;base64,AA==',
  'latitude': 48.0,
  'longitude': 2.0,
};

Map<String, dynamic> cloudRecordJson({
  required String pictureKey,
  required DateTime updateAt,
  DateTime? createdAt,
  DateTime? deletedAt,
  double height = 100,
  double width = 200,
}) => {
  'pictureId': pictureKey,
  'originalId': null,
  'createdAt': (createdAt ?? updateAt).millisecondsSinceEpoch,
  'updateAt': updateAt.millisecondsSinceEpoch,
  'visitedAt': null,
  'height': height,
  'width': width,
  if (deletedAt != null) 'deletedAt': deletedAt.millisecondsSinceEpoch,
};

CloudMetadata cloudMetadata({
  required String id,
  required DateTime updatedAt,
  DateTime? createdAt,
  DateTime? deletedAt,
}) => CloudMetadata(
  id: id,
  createdAt: createdAt ?? updatedAt,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
);

MockCloudSyncProvider createProvider({String id = 'mock'}) {
  return MockCloudSyncProvider(
    collectionNames: {Record: 'records', Picture: 'pictures'},
    id: id,
  );
}

void main() {
  group('CloudSyncService', () {
    test('isActive returns false when no provider is set', () async {
      final db = await databaseFactoryMemory.openDatabase('test_no_provider.db');
      final localService = DatabaseService(db: db);
      final service = CloudSyncService(databaseService: localService);

      expect(service.isActive, false);

      await service.dispose();
      await db.close();
    });

    test('isActive returns true after setProvider', () async {
      final db = await databaseFactoryMemory.openDatabase('test_active.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      expect(syncService.isActive, true);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('setProvider halts sync when provider.initialize fails', () async {
      final db = await databaseFactoryMemory.openDatabase('test_initialize_fails.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      mockProvider.failInitialize = true;
      final syncService = CloudSyncService(databaseService: dbService);

      await syncService.setProvider(mockProvider);

      expect(syncService.isActive, false);
      expect(syncService.pictures, isNull);
      expect(syncService.records, isNull);

      final picture = await insertPicture(dbService, id: 'pic1', provider: 'pastvu');
      await insertRecord(dbService, picture);

      await Future.delayed(const Duration(milliseconds: 200));
      expect(await mockProvider.listRecords('records'), isEmpty);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud does nothing when local and cloud are empty', () async {
      final db = await databaseFactoryMemory.openDatabase('test_empty_sync.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
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
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);

      final picture = await insertPicture(dbService, id: 'pic1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);

      await syncService.setProvider(mockProvider);

      final cloudRecords = await mockProvider.listRecords('records');
      expect(cloudRecords, hasLength(1));
      expect(cloudRecords.first.id, 'pastvu/pic1');
      expect(mockProvider.hasRecord('pictures', 'pastvu/pic1'), true);

      final mirror = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(mirror, isNotNull);
      expect(mirror!.cloudId, 'mock');

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('record without a picture is not pushed to cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_push_no_picture.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final record = Record(
        pictureId: 0,
        createdAt: now,
        updateAt: now,
      );
      await dbService.createRepository<Record>().insert(record);

      await Future.delayed(const Duration(milliseconds: 200));
      await syncService.syncWithCloud();

      final cloudRecords = await mockProvider.listRecords('records');
      expect(cloudRecords, isEmpty);

      final localRecords = await dbService.createRepository<Record>().list();
      expect(localRecords, hasLength(1));
      expect(await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock'), isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pull cloud records to local via syncWithCloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pull_cloud.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/c1', cloudPictureJson(id: 'c1', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/c1', cloudRecordJson(pictureKey: 'pastvu/c1', updateAt: now, width: 200));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final localRepo = dbService.createRepository<Record>();
      final localRecords = await localRepo.list();
      expect(localRecords, hasLength(1));
      expect(localRecords.first.width, 200.0);

      final localPicture = await dbService.createRepository<Picture>()
          .findPictureByIdAndProvider('c1', 'pastvu');
      expect(localPicture, isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('_loadRecord: incoming newer than local overwrites local', () async {
      final db = await databaseFactoryMemory.openDatabase('test_newer_incoming.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final earlier = DateTime(2024, 1, 1);
      final later = DateTime(2024, 6, 1);

      final picture = await insertPicture(dbService, id: 'p1', provider: 'pastvu');
      await insertRecord(dbService, picture, updateAt: earlier);

      mockProvider.addRecord('pictures', 'pastvu/p1', cloudPictureJson(id: 'p1', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/p1', cloudRecordJson(pictureKey: 'pastvu/p1', updateAt: later, height: 200, width: 300));

      final pulled = await syncService.records!.pullRecord(cloudMetadata(id: 'pastvu/p1', updatedAt: later));
      expect(pulled, isNotNull);
      expect(pulled!.record!.height, 200.0);

      final localCopy = await recordRepo.findRecordByPictureId(picture.localId!);
      expect(localCopy, isNotNull);
      expect(localCopy!.height, 200.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('_loadRecord: incoming older than local keeps local', () async {
      final db = await databaseFactoryMemory.openDatabase('test_older_incoming.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final earlier = DateTime(2024, 1, 1);
      final later = DateTime(2024, 6, 1);

      final picture = await insertPicture(dbService, id: 'p2', provider: 'pastvu');
      await insertRecord(dbService, picture, updateAt: later, height: 500, width: 600);

      mockProvider.addRecord('pictures', 'pastvu/p2', cloudPictureJson(id: 'p2', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/p2', cloudRecordJson(pictureKey: 'pastvu/p2', updateAt: earlier, height: 100, width: 200));

      final pulled = await syncService.records!.pullRecord(cloudMetadata(id: 'pastvu/p2', updatedAt: earlier));
      expect(pulled, isNotNull);
      expect(pulled!.record!.height, 500.0);

      final localCopy = await recordRepo.findRecordByPictureId(picture.localId!);
      expect(localCopy, isNotNull);
      expect(localCopy!.height, 500.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('pushRecord creates a mirror and pushes to cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_push_record_cloudid.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final picture = await insertPicture(dbService, id: 'pic3', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);
      record.picture = picture;

      final mirror = await syncService.records!.pushRecord(record);

      expect(mirror, isNotNull);
      expect(mirror!.cloudId, 'mock');
      expect(mockProvider.hasRecord('records', 'pastvu/pic3'), true);
      expect(mockProvider.hasRecord('pictures', 'pastvu/pic3'), true);

      final localCopy = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(localCopy, isNotNull);
      expect(localCopy!.cloudId, 'mock');

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud pulls multiple cloud records', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pull_records_count.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      for (int i = 0; i < 3; i++) {
        final key = 'pastvu/cr_$i';
        mockProvider.addRecord('pictures', key, cloudPictureJson(id: 'cr_$i', provider: 'pastvu'));
        mockProvider.addRecord('records', key, cloudRecordJson(pictureKey: key, updateAt: now.add(Duration(hours: i)), height: 100.0 + i, width: 200.0 + i));
      }

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final records = await dbService.createRepository<Record>().list();
      expect(records, hasLength(3));

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('deleting a synced record removes it from the cloud and the picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_delete_record.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = await insertPicture(dbService, id: 'del_pic', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);
      record.picture = picture;
      await syncService.records!.pushRecord(record);

      expect(mockProvider.hasRecord('records', 'pastvu/del_pic'), true);
      expect(mockProvider.hasRecord('pictures', 'pastvu/del_pic'), true);

      await dbService.createRepository<Record>().delete(record.localId!);
      await Future.delayed(const Duration(milliseconds: 300));

      expect(mockProvider.hasRecord('records', 'pastvu/del_pic'), false);
      expect(mockProvider.hasRecord('pictures', 'pastvu/del_pic'), false);
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull);
      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud syncs local updates to existing cloud records', () async {
      final db = await databaseFactoryMemory.openDatabase('test_sync_update.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();

      final picture = await insertPicture(dbService, id: 'upd1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: now, height: 100, width: 200);

      await Future.delayed(const Duration(milliseconds: 200));

      record.height = 999;
      record.updateAt = now.add(const Duration(hours: 1));
      await recordRepo.update(record);

      await Future.delayed(const Duration(milliseconds: 200));
      await syncService.syncWithCloud();

      final cloudData = mockProvider.getRecordData('records', 'pastvu/upd1');
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
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = await insertPicture(dbService, id: 'ev_pic', provider: 'pastvu');
      final record = await insertRecord(dbService, picture);

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockProvider.hasRecord('records', 'pastvu/ev_pic'), true);
      expect(await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock'), isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud with conflicting records pushes local when newer', () async {
      final db = await databaseFactoryMemory.openDatabase('test_conflict.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final older = now.subtract(const Duration(days: 1));

      final picture = await insertPicture(dbService, id: 'conf', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: now, height: 777, width: 888);

      await dbService.createRepository<RecordMirror>().insert(RecordMirror(
        id: 'pastvu/conf',
        recordId: record.localId!,
        createdAt: older,
        updatedAt: older,
        cloudId: 'mock',
      ));
      await dbService.createRepository<PictureMirror>().insert(PictureMirror(
        id: 'pastvu/conf',
        pictureId: picture.localId!,
        createdAt: older,
        updatedAt: older,
        cloudId: 'mock',
      ));

      mockProvider.addRecord('pictures', 'pastvu/conf', cloudPictureJson(id: 'conf', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/conf', cloudRecordJson(pictureKey: 'pastvu/conf', updateAt: older, height: 100, width: 200));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final cloudData = mockProvider.getRecordData('records', 'pastvu/conf');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 777);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud keeps cloud when cloud is newer', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_newer.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final older = now.subtract(const Duration(days: 1));

      final picture = await insertPicture(dbService, id: 'newer', provider: 'pastvu');
      await insertRecord(dbService, picture, updateAt: older, height: 777, width: 888);

      mockProvider.addRecord('pictures', 'pastvu/newer', cloudPictureJson(id: 'newer', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/newer', cloudRecordJson(pictureKey: 'pastvu/newer', updateAt: now, height: 100, width: 200));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final cloudData = mockProvider.getRecordData('records', 'pastvu/newer');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 100.0);

      final localCopy = await recordRepo.findRecordByPictureId(picture.localId!);
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
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/c_ins', cloudPictureJson(id: 'c_ins', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/c_ins', cloudRecordJson(pictureKey: 'pastvu/c_ins', updateAt: now, width: 250));
      mockProvider.emitChange(CloudInsertedEvent(
        metadata: cloudMetadata(id: 'pastvu/c_ins', updatedAt: now),
        collection: 'records',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

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
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      final now = DateTime.now();

      final picture = await insertPicture(dbService, id: 'upd_evt', provider: 'pastvu');
      await insertRecord(dbService, picture, updateAt: now, height: 10, width: 20);

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      await Future.delayed(const Duration(milliseconds: 200));

      mockProvider.addRecord('pictures', 'pastvu/upd_evt', cloudPictureJson(id: 'upd_evt', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/upd_evt', cloudRecordJson(pictureKey: 'pastvu/upd_evt', updateAt: now.add(const Duration(hours: 2)), height: 99, width: 199));
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: cloudMetadata(id: 'pastvu/upd_evt', updatedAt: now.add(const Duration(hours: 2))),
        collection: 'records',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      final recordRepo = dbService.createRepository<Record>();
      final updated = await recordRepo.findRecordByPictureId(picture.localId!);
      expect(updated, isNotNull);
      expect(updated!.height, 99.0);
      expect(updated.width, 199.0);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudDeletedEvent removes local record and picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_cloud_deleted.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = await insertPicture(dbService, id: 'del_evt', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, height: 10, width: 20);

      await Future.delayed(const Duration(milliseconds: 200));

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/del_evt', cloudPictureJson(id: 'del_evt', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/del_evt', cloudRecordJson(pictureKey: 'pastvu/del_evt', updateAt: now));

      mockProvider.emitChange(CloudDeletedEvent(
        metadata: cloudMetadata(id: 'pastvu/del_evt', updatedAt: now, deletedAt: now),
        collection: 'records',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      final recordRepo = dbService.createRepository<Record>();
      final pictureRepo = dbService.createRepository<Picture>();
      expect(await recordRepo.findRecordByPictureId(picture.localId!), isNull);
      final deletedPic = await pictureRepo.getById(picture.localId!);
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
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/rec_1', cloudPictureJson(id: 'rec_1', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/rec_1', cloudRecordJson(pictureKey: 'pastvu/rec_1', updateAt: now, width: 400));
      mockProvider.emitChange(const CloudReconnectedEvent());

      await Future.delayed(const Duration(milliseconds: 200));

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
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/unk_1', cloudPictureJson(id: 'unk_1', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/unk_1', cloudRecordJson(pictureKey: 'pastvu/unk_1', updateAt: now, width: 60));
      mockProvider.emitChange();

      await Future.delayed(const Duration(milliseconds: 200));

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
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final recordRepo = dbService.createRepository<Record>();
      final now = DateTime.now();
      final picture = await insertPicture(dbService, id: 'ent_upd', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: now, height: 100, width: 200);
      record.picture = picture;

      await syncService.records!.pushRecord(record);
      expect(await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock'), isNotNull);

      record.height = 999;
      record.updateAt = now.add(const Duration(hours: 1));
      await recordRepo.update(record);

      await Future.delayed(const Duration(milliseconds: 200));

      final cloudData = mockProvider.getRecordData('records', 'pastvu/ent_upd');
      expect(cloudData, isNotNull);
      expect(cloudData!['height'], 999);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('EntityRemoved event removes record from cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_entity_removed.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final picture = await insertPicture(dbService, id: 'ent_rem', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: now);
      record.picture = picture;
      await syncService.records!.pushRecord(record);

      expect(mockProvider.hasRecord('records', 'pastvu/ent_rem'), true);

      await dbService.createRepository<Record>().delete(record.localId!);
      await Future.delayed(const Duration(milliseconds: 300));

      expect(mockProvider.hasRecord('records', 'pastvu/ent_rem'), false);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('changing provider re-pushes to the new provider without duplicating', () async {
      final db = await databaseFactoryMemory.openDatabase('test_provider_change.db');
      final dbService = DatabaseService(db: db);

      final now = DateTime.now();
      final picture = await insertPicture(dbService, id: 'p1', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: now);

      final syncService = CloudSyncService(databaseService: dbService);

      final providerA = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'prov_a',
      );
      await syncService.setProvider(providerA);

      expect(providerA.hasRecord('records', 'pastvu/p1'), true);
      expect(providerA.hasRecord('pictures', 'pastvu/p1'), true);
      expect(await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'prov_a'), isNotNull);

      final providerB = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'prov_b',
      );
      await syncService.setProvider(providerB);

      expect(providerB.hasRecord('records', 'pastvu/p1'), true);
      expect(providerA.hasRecord('records', 'pastvu/p1'), true);
      expect(await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'prov_b'), isNotNull);

      await syncService.setProvider(providerA);

      expect(providerA.hasRecord('records', 'pastvu/p1'), true);
      expect(providerA.getCollectionSize('records'), 1);
      expect(providerA.getCollectionSize('pictures'), 1);
      expect(providerB.getCollectionSize('records'), 1);

      await syncService.dispose();
      providerA.dispose();
      providerB.dispose();
      await db.close();
    });

    test('syncWithCloud pushes a standalone picture to the cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_standalone_pic_push.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      final picture = Picture(
        id: 'solo1',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
        visitedAt: now,
      );
      await dbService.createRepository<Picture>().insert(picture);

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      expect(mockProvider.hasRecord('pictures', 'pastvu/solo1'), true);
      expect(mockProvider.hasRecord('records', 'pastvu/solo1'), false);
      final mirror = await dbService.createRepository<PictureMirror>()
          .findByPictureAndCloud(picture.localId!, 'mock');
      expect(mirror, isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud pulls a standalone picture from the cloud', () async {
      final db = await databaseFactoryMemory.openDatabase('test_standalone_pic_pull.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      mockProvider.addRecord('pictures', 'pastvu/c1', cloudPictureJson(id: 'c1', provider: 'pastvu'));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final pictures = await dbService.createRepository<Picture>().list();
      expect(pictures, hasLength(1));
      expect(pictures.first.id, 'c1');
      expect(pictures.first.provider, 'pastvu');
      expect(await dbService.createRepository<PictureMirror>()
          .findByIdAndCloud('pastvu/c1', 'mock'), isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud re-pushes a re-visited standalone picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_standalone_pic_revisit.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final synced = DateTime.now().subtract(const Duration(hours: 1));
      final picture = Picture(
        id: 'solo2',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
        visitedAt: synced,
      );
      await dbService.createRepository<Picture>().insert(picture);

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);
      expect(mockProvider.hasRecord('pictures', 'pastvu/solo2'), true);

      final revisited = DateTime.now().add(const Duration(minutes: 1));
      picture.visitedAt = revisited;
      await dbService.createRepository<Picture>().update(picture);

      await syncService.syncWithCloud();

      final cloudData = mockProvider.getRecordData('pictures', 'pastvu/solo2');
      expect(cloudData?['visitedAt'], revisited.millisecondsSinceEpoch);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud does not duplicate a picture that belongs to a record', () async {
      final db = await databaseFactoryMemory.openDatabase('test_standalone_pic_record.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      final picture = await insertPicture(dbService, id: 'p2', provider: 'pastvu');
      picture.visitedAt = now;
      await dbService.createRepository<Picture>().update(picture);
      await insertRecord(dbService, picture, updateAt: now);

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      expect(mockProvider.getCollectionSize('pictures'), 1);
      expect(mockProvider.hasRecord('pictures', 'pastvu/p2'), true);
      expect(mockProvider.hasRecord('records', 'pastvu/p2'), true);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('syncWithCloud does not pull a picture that belongs to a live cloud record', () async {
      final db = await databaseFactoryMemory.openDatabase('test_standalone_pic_live_record.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/p3', cloudPictureJson(id: 'p3', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/p3', cloudRecordJson(
        pictureKey: 'pastvu/p3',
        updateAt: now,
      ));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final pictures = await dbService.createRepository<Picture>().list();
      expect(pictures, hasLength(1));
      expect(pictures.first.id, 'p3');
      expect(await dbService.createRepository<Record>().list(), hasLength(1));

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudInsertedEvent on pictures collection pulls a standalone picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pic_cloud_inserted.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/ev_ins', cloudPictureJson(id: 'ev_ins', provider: 'pastvu'));
      mockProvider.emitChange(CloudInsertedEvent(
        metadata: cloudMetadata(id: 'pastvu/ev_ins', updatedAt: now),
        collection: 'pictures',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      final pictures = await dbService.createRepository<Picture>().list();
      expect(pictures, hasLength(1));
      expect(pictures.first.id, 'ev_ins');
      expect(await dbService.createRepository<PictureMirror>()
          .findByIdAndCloud('pastvu/ev_ins', 'mock'), isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudUpdatedEvent on pictures collection updates a local standalone picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pic_cloud_updated.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final picture = Picture(
        id: 'ev_upd',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
        description: 'old',
      );
      await dbService.createRepository<Picture>().insert(picture);

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/ev_upd', {
        ...cloudPictureJson(id: 'ev_upd', provider: 'pastvu'),
        'description': 'new',
      });
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: cloudMetadata(id: 'pastvu/ev_upd', updatedAt: now),
        collection: 'pictures',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      final pictures = await dbService.createRepository<Picture>().list();
      expect(pictures, hasLength(1));
      expect(pictures.first.id, 'ev_upd');
      expect(pictures.first.description, 'new');

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudDeletedEvent on pictures collection removes a local standalone picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pic_cloud_deleted.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      final now = DateTime.now();
      final picture = Picture(
        id: 'ev_del',
        provider: 'pastvu',
        url: 'data:image/jpg;base64,AA==',
        latitude: 48.0,
        longitude: 2.0,
        visitedAt: now,
      );
      await dbService.createRepository<Picture>().insert(picture);

      await syncService.syncWithCloud();
      final mirror = await dbService.createRepository<PictureMirror>()
          .findByPictureAndCloud(picture.localId!, 'mock');
      expect(mirror, isNotNull);

      mockProvider.emitChange(CloudDeletedEvent(
        metadata: cloudMetadata(
          id: 'pastvu/ev_del',
          updatedAt: now.add(const Duration(minutes: 1)),
          deletedAt: now.add(const Duration(minutes: 1)),
        ),
        collection: 'pictures',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);
      final deletedMirror = await dbService.createRepository<PictureMirror>()
          .findByPictureAndCloud(picture.localId!, 'mock');
      expect(deletedMirror, isNotNull);
      expect(deletedMirror!.deletedAt, isNotNull);

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('CloudInsertedEvent on pictures collection does not duplicate a record picture', () async {
      final db = await databaseFactoryMemory.openDatabase('test_pic_cloud_inserted_record.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );

      final now = DateTime.now();
      mockProvider.addRecord('pictures', 'pastvu/ev_rcd', cloudPictureJson(id: 'ev_rcd', provider: 'pastvu'));
      mockProvider.addRecord('records', 'pastvu/ev_rcd', cloudRecordJson(
        pictureKey: 'pastvu/ev_rcd',
        updateAt: now,
      ));

      final syncService = CloudSyncService(databaseService: dbService);
      await syncService.setProvider(mockProvider);

      mockProvider.emitChange(CloudInsertedEvent(
        metadata: cloudMetadata(
          id: 'pastvu/ev_rcd',
          updatedAt: now.add(const Duration(hours: 1)),
        ),
        collection: 'pictures',
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      final pictures = await dbService.createRepository<Picture>().list();
      expect(pictures, hasLength(1));
      expect(await dbService.createRepository<Record>().list(), hasLength(1));

      await syncService.dispose();
      mockProvider.dispose();
      await db.close();
    });

    test('first sync with existing mirrors resumes incrementally from the oldest mirror', () async {
      final db = await databaseFactoryMemory.openDatabase('test_oldest_mirror_seed.db');
      final dbService = DatabaseService(db: db);
      final mockProvider = createProvider();

      final now = DateTime.now();
      mockProvider.addRecord('records', 'pastvu/r1', cloudRecordJson(
        pictureKey: 'pastvu/r1',
        updateAt: now.subtract(const Duration(hours: 1)),
      ));
      mockProvider.addRecord('pictures', 'pastvu/r1', cloudPictureJson(id: 'r1', provider: 'pastvu'));

      final firstSync = CloudSyncService(databaseService: dbService);
      await firstSync.setProvider(mockProvider);
      expect(await dbService.createRepository<Record>().list(), hasLength(1));
      expect(await dbService.createRepository<Picture>().list(), hasLength(1));
      await firstSync.dispose();

      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      mockProvider.addRecord('records', 'pastvu/r_old', cloudRecordJson(
        pictureKey: 'pastvu/r_old',
        updateAt: twoHoursAgo,
      ));
      mockProvider.addRecord('pictures', 'pastvu/r_old', {
        ...cloudPictureJson(id: 'r_old', provider: 'pastvu'),
        'updateAt': twoHoursAgo.millisecondsSinceEpoch,
      });

      final secondSync = CloudSyncService(databaseService: dbService);
      await secondSync.setProvider(mockProvider);

      final records = await dbService.createRepository<Record>().list();
      expect(records, hasLength(1));
      final r1 = await dbService.createRepository<Picture>().findPictureByIdAndProvider('r1', 'pastvu');
      expect(r1, isNotNull);
      expect(records.first.pictureId, r1!.localId);
      expect(await dbService.createRepository<Picture>().list(), hasLength(1));

      await secondSync.dispose();
      mockProvider.dispose();
      await db.close();
    });
  });
}
