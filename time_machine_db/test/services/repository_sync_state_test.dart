import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('SyncStateRepository extension', () {
    late Database db;
    late Repository<SyncState> syncStateRepo;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_sync_state_${DateTime.now().millisecondsSinceEpoch}.db');
      syncStateRepo = Repository<SyncState>.create(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('findByCloudId returns null when no state exists', () async {
      final result = await syncStateRepo.findByCloudId('mock');
      expect(result, isNull);
    });

    test('inserted sync state is persisted and found by cloud id', () async {
      final date = DateTime.utc(2026, 9, 14, 12);
      await syncStateRepo.insert(SyncState(cloudId: 'mock', lastSync: date));

      final result = await syncStateRepo.findByCloudId('mock');
      expect(result, isNotNull);
      expect(result!.lastSync.millisecondsSinceEpoch, date.millisecondsSinceEpoch);
    });

    test('update overwrites the lastSync of an existing state', () async {
      final date = DateTime.utc(2026, 9, 14, 12);
      final later = date.add(const Duration(hours: 1));
      final state = await syncStateRepo.insert(SyncState(cloudId: 'mock', lastSync: date));

      state.lastSync = later;
      await syncStateRepo.update(state);

      final result = await syncStateRepo.findByCloudId('mock');
      expect(result, isNotNull);
      expect(result!.lastSync.millisecondsSinceEpoch, later.millisecondsSinceEpoch);
      expect((await syncStateRepo.list()), hasLength(1));
    });

    test('findByCloudId distinguishes between clouds', () async {
      await syncStateRepo.insert(SyncState(cloudId: 'cloud_a', lastSync: DateTime.utc(2026, 1, 1)));
      await syncStateRepo.insert(SyncState(cloudId: 'cloud_b', lastSync: DateTime.utc(2026, 2, 1)));

      final a = await syncStateRepo.findByCloudId('cloud_a');
      final b = await syncStateRepo.findByCloudId('cloud_b');
      expect(a!.cloudId, 'cloud_a');
      expect(b!.cloudId, 'cloud_b');
    });
  });
}