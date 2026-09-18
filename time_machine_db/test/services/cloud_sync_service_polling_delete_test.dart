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

CloudMetadata tombstone(String id, DateTime deletedAt) => CloudMetadata(
  id: id,
  createdAt: deletedAt.subtract(const Duration(days: 3)),
  updatedAt: deletedAt,
  deletedAt: deletedAt,
);

void main() {
  group('CloudSyncService polling changes delete propagation', () {
    Future<(DatabaseService, CloudSyncService, MockCloudSyncProvider, Picture, Record)> setup(
      String dbName,
      String id,
      DateTime syncedAt,
    ) async {
      final db = await databaseFactoryMemory.openDatabase(dbName);
      final dbService = DatabaseService(db: db);

      final picture = await insertPicture(dbService, id: id, provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: syncedAt);
      await dbService.createRepository<PictureMirror>().insert(PictureMirror(
        id: 'pastvu/$id',
        pictureId: picture.localId!,
        createdAt: syncedAt,
        updatedAt: syncedAt,
        cloudId: 'mock',
      ));
      await dbService.createRepository<RecordMirror>().insert(RecordMirror(
        id: 'pastvu/$id',
        recordId: record.localId!,
        createdAt: syncedAt,
        updatedAt: syncedAt,
        cloudId: 'mock',
      ));

      final mockProvider = MockCloudSyncProvider(
        collectionNames: {Record: 'records', Picture: 'pictures'},
        id: 'mock',
        supportsEvents: true,
      );
      // Already-synced state on the cloud, so the initial sync does not re-push.
      mockProvider.addRecord('pictures', 'pastvu/$id', {
        'id': id,
        'provider': 'pastvu',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 48.0,
        'longitude': 2.0,
        'createdAt': syncedAt.millisecondsSinceEpoch,
        'updateAt': syncedAt.millisecondsSinceEpoch,
      });
      mockProvider.addRecord('records', 'pastvu/$id', {
        'pictureId': 'pastvu/$id',
        'originalId': null,
        'createdAt': syncedAt.millisecondsSinceEpoch,
        'updateAt': syncedAt.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      });

      final syncService = CloudSyncService();
      await syncService.init(databaseService: dbService, provider: mockProvider);
      return (dbService, syncService, mockProvider, picture, record);
    }

    test('deletes record along with its picture even when the record mirror is newer than the cloud tombstone', () async {
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_stale_record.db', 'pst', DateTime.now().subtract(const Duration(hours: 2)));
      final now = DateTime.now();
      final deletedAt = now.subtract(const Duration(hours: 1));

      // The record was edited/pushed on this device AFTER the cloud deletion
      // (e.g. viewing it bumped RecordMirror.updatedAt), so its tombstone is
      // considered stale by pullRecord. The picture, whose mirror is older,
      // still gets deleted; the record must not be left orphaned.
      final recordMirrorRepo = dbService.createRepository<RecordMirror>();
      final rm = await recordMirrorRepo.findByRecordAndCloud(record.localId!, 'mock');
      rm!.updatedAt = now.subtract(const Duration(minutes: 30));
      await recordMirrorRepo.update(rm);

      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pst', deletedAt),
        collection: 'pictures',
        data: const {},
      ));
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pst', deletedAt),
        collection: 'records',
        data: const {},
      ));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull,
          reason: 'Picture should have been deleted');
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull,
          reason: 'Record referencing the deleted picture should have been deleted too');

      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });

    test('deleting a picture removes the owning record but not records using it as an original', () async {
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_multi.db', 'pmu', DateTime.now().subtract(const Duration(hours: 2)));

      // A record that merely references the picture as its "then"/original must
      // survive; only the record owning the picture via pictureId is removed.
      final other = await insertPicture(dbService, id: 'pmu_other', provider: 'pastvu');
      final time = DateTime.now().subtract(const Duration(hours: 2));
      final borrowed = Record(
        pictureId: other.localId!,
        originalId: picture.localId!,
        createdAt: time,
        updateAt: time,
      );
      await dbService.createRepository<Record>().insert(borrowed);

      await syncService.pictures!.deleteFromDB(picture.localId!);

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull,
          reason: 'Record owning the deleted picture should be removed');
      expect(await dbService.createRepository<Record>().getById(borrowed.localId!), isNotNull,
          reason: 'Record referencing the picture only as an original should survive');
      final mirror = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(mirror?.deletedAt, isNotNull,
          reason: 'Record mirror of the removed record should be tombstoned so sync drops it');

      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });

    test('cloud tombstone updates for a synced record delete picture and record locally', () async {
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_updated.db', 'pup', DateTime.now().subtract(const Duration(hours: 2)));
      final deletedAt = DateTime.now().subtract(const Duration(hours: 1));

      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pup', deletedAt),
        collection: 'pictures',
        data: const {},
      ));
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pup', deletedAt),
        collection: 'records',
        data: const {},
      ));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });

    test('cloud delete events for picture and record delete both locally', () async {
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_deleted.db', 'pdl', DateTime.now().subtract(const Duration(hours: 2)));
      final deletedAt = DateTime.now().subtract(const Duration(hours: 1));

      mockProvider.emitChange(CloudDeletedEvent(
        metadata: tombstone('pastvu/pdl', deletedAt),
        collection: 'pictures',
      ));
      mockProvider.emitChange(CloudDeletedEvent(
        metadata: tombstone('pastvu/pdl', deletedAt),
        collection: 'records',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull);

      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });

    test('record tombstone whose date equals _lastChange still deletes and fires dbUpdated', () async {
      final syncedAt = DateTime.now().subtract(const Duration(hours: 2));
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_equal_cursor.db', 'pec', syncedAt);

      // A newer record makes the sync cursor (lastChange) land exactly on S2,
      // which is still newer than the target record's own mirror.
      final newerAt = DateTime.now().subtract(const Duration(minutes: 30));
      final newerPicture = await insertPicture(dbService, id: 'pec_newer', provider: 'pastvu');
      await insertRecord(dbService, newerPicture, updateAt: newerAt);
      mockProvider.addRecord('pictures', 'pastvu/pec_newer', {
        'id': 'pec_newer',
        'provider': 'pastvu',
        'url': 'data:image/jpg;base64,AA==',
        'latitude': 48.0,
        'longitude': 2.0,
        'createdAt': newerAt.millisecondsSinceEpoch,
        'updateAt': newerAt.millisecondsSinceEpoch,
      });
      mockProvider.addRecord('records', 'pastvu/pec_newer', {
        'pictureId': 'pastvu/pec_newer',
        'originalId': null,
        'createdAt': newerAt.millisecondsSinceEpoch,
        'updateAt': newerAt.millisecondsSinceEpoch,
        'visitedAt': null,
        'height': 100.0,
        'width': 200.0,
      });
      await syncService.syncWithCloud();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      var dbUpdatedFired = false;
      final sub = syncService.dbUpdated.listen((_) => dbUpdatedFired = true);

      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pec', newerAt),
        collection: 'records',
        data: const {},
      ));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull,
          reason: 'Record tombstone at exactly lastChange must still be applied');
      expect(dbUpdatedFired, isTrue,
          reason: 'Deletion at the cursor boundary should still refresh the UI');

      await sub.cancel();
      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });

    test('record tombstone after the picture cascade still bumps the RecordMirror to the record deletion date', () async {
      final (dbService, syncService, mockProvider, picture, record) =
          await setup('poll_cascade_order.db', 'pco', DateTime.now().subtract(const Duration(hours: 2)));
      final pictureDeletedAt = DateTime.now().subtract(const Duration(hours: 1));
      final recordDeletedAt = DateTime.now().subtract(const Duration(minutes: 30));

      // Picture tombstone first: the cascade removes the Record row and
      // tombstones its mirror at the picture date. The record's own tombstone,
      // being newer, must still update the mirror (previously deleteFromDB
      // bailed out because the Record row was already gone).
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pco', pictureDeletedAt),
        collection: 'pictures',
        data: const {},
      ));
      mockProvider.emitChange(CloudUpdatedEvent(
        metadata: tombstone('pastvu/pco', recordDeletedAt),
        collection: 'records',
        data: const {},
      ));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(await dbService.createRepository<Picture>().getById(picture.localId!), isNull);
      expect(await dbService.createRepository<Record>().getById(record.localId!), isNull);
      final mirror = await dbService.createRepository<RecordMirror>()
          .findByRecordAndCloud(record.localId!, 'mock');
      expect(mirror?.deletedAt?.millisecondsSinceEpoch, recordDeletedAt.millisecondsSinceEpoch,
          reason: 'RecordMirror must be tombstoned at the record deletion date');

      await syncService.dispose();
      mockProvider.dispose();
      await dbService.db.close();
    });
  });
}