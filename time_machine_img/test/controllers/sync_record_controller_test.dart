import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/sync_record_controller.dart';

import '../helpers/cloud_test_utils.dart';

/// Minimal host mixing in the record watcher, like the real controllers do.
class _RecordWatcher with SyncRecordController {}

void main() {
  group('SyncRecordController', () {
    late Database db;
    late DatabaseService dbService;
    late FakeCloudSyncProvider provider;
    late CloudSyncService sync;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'sync_record_controller_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      dbService = DatabaseService(db: db);
      provider = createTestProvider();
      sync = CloudSyncService();

      addTearDown(() async => await db.close());
      addTearDown(() async => await sync.dispose());
      addTearDown(provider.dispose);
    });

    /// Seeds a picture + record, lets the initial cloud sync push them, then
    /// starts watching the record (returning the observed emissions).
    Future<(Record, _RecordWatcher, List<Record?>)> seedAndWatch() async {
      final updateAt = DateTime.now();
      final picture =
          await insertPicture(dbService, id: 'rec_pic', provider: 'pastvu');
      final record = await insertRecord(dbService, picture, updateAt: updateAt);
      await sync.init(databaseService: dbService, provider: provider);

      final watcher = _RecordWatcher();
      final emissions = <Record?>[];
      watcher.recordChanges.listen(emissions.add);
      watcher.watchSyncRecord(
        cloudSyncService: sync,
        databaseService: dbService,
        entityId: record.localId,
      );
      addTearDown(watcher.disposeSyncRecord);

      await waitUntil(() => emissions.isNotEmpty);
      return (record, watcher, emissions);
    }

    test('emits the initial record on watch', () async {
      final (record, _, emissions) = await seedAndWatch();

      expect(emissions.length, 1);
      expect(emissions.single!.localId, record.localId);
      expect(emissions.single!.picture, isNotNull);
    });

    test('re-emits when syncWithCloud pulls a cloud update with a newer '
        'updateAt', () async {
      final (_, _, emissions) = await seedAndWatch();
      final newUpdateAt = DateTime.now().add(const Duration(hours: 1));
      const key = 'pastvu/rec_pic';

      provider.addRecord('pictures', key,
          cloudPictureJson(id: 'rec_pic', provider: 'pastvu'));
      provider.addRecord('records', key, cloudRecordJson(
        pictureKey: key,
        updateAt: newUpdateAt,
        height: 321,
        width: 432,
      ));

      await sync.syncWithCloud();

      await waitUntil(
        () => emissions.isNotEmpty &&
            emissions.last!.updateAt.millisecondsSinceEpoch ==
                newUpdateAt.millisecondsSinceEpoch,
      );
      expect(emissions.last!.height, 321);
      expect(emissions.last!.width, 432);
    });

    test('does not re-emit when a sync changes nothing (updateAt unchanged)',
        () async {
      final (_, _, emissions) = await seedAndWatch();
      final initialCount = emissions.length;

      await sync.syncWithCloud();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.length, initialCount,
          reason: 'an unchanged UpdateAt fingerprint must not be re-published');
    });

    test('re-emits when a CloudUpdatedEvent changes the record', () async {
      final (_, _, emissions) = await seedAndWatch();
      final newUpdateAt = DateTime.now().add(const Duration(hours: 2));
      const key = 'pastvu/rec_pic';

      provider.addRecord('pictures', key,
          cloudPictureJson(id: 'rec_pic', provider: 'pastvu'));
      provider.addRecord('records', key, cloudRecordJson(
        pictureKey: key,
        updateAt: newUpdateAt,
        height: 555,
        width: 666,
      ));
      provider.emitChange(CloudUpdatedEvent(
        metadata: cloudMetadata(id: key, updatedAt: newUpdateAt),
        collection: 'records',
      ));

      await waitUntil(
        () => emissions.isNotEmpty &&
            emissions.last!.updateAt.millisecondsSinceEpoch ==
                newUpdateAt.millisecondsSinceEpoch,
      );
      expect(emissions.last!.height, 555);
      expect(emissions.last!.width, 666);
    });

    test('fires recordDeleted once when a CloudDeletedEvent removes the record',
        () async {
      final (record, watcher, _) = await seedAndWatch();
      final deleted = <void>[];
      watcher.recordDeleted.listen((_) => deleted.add(null));
      const key = 'pastvu/rec_pic';
      final deletedAt = DateTime.now().add(const Duration(hours: 1));

      provider.emitChange(CloudDeletedEvent(
        metadata: cloudMetadata(
          id: key,
          updatedAt: deletedAt,
          deletedAt: deletedAt,
        ),
        collection: 'records',
      ));

      await waitUntil(() => deleted.isNotEmpty);
      expect(deleted.length, 1);
      expect(
        await dbService.createRepository<Record>().getById(record.localId!),
        isNull,
      );
    });
  });
}