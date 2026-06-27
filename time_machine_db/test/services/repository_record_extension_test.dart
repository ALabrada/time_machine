import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('RecordRepository extension', () {
    late Database db;
    late Repository<Record> recordRepo;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_rec_ext_${DateTime.now().millisecondsSinceEpoch}.db');
      recordRepo = Repository<Record>.create(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('findRecordsWithPictures filters by picture IDs', () async {
      final r1 = Record(pictureId: 1, createdAt: DateTime.now(), updateAt: DateTime.now());
      final r2 = Record(pictureId: 2, createdAt: DateTime.now(), updateAt: DateTime.now());
      final r3 = Record(pictureId: 3, createdAt: DateTime.now(), updateAt: DateTime.now());
      await recordRepo.insert(r1);
      await recordRepo.insert(r2);
      await recordRepo.insert(r3);
      final results = await recordRepo.findRecordsWithPictures([1, 3]);
      expect(results.length, 2);
      expect(results.map((r) => r.pictureId), containsAll([1, 3]));
    });

    test('findRecordsWithPictures also matches originalId', () async {
      final r1 = Record(pictureId: 10, originalId: 100, createdAt: DateTime.now(), updateAt: DateTime.now());
      await recordRepo.insert(r1);
      final results = await recordRepo.findRecordsWithPictures([100]);
      expect(results.length, 1);
      expect(results.first.pictureId, 10);
    });

    test('findRecordsWithPictures returns empty for no matches', () async {
      final results = await recordRepo.findRecordsWithPictures([999]);
      expect(results, isEmpty);
    });

    test('findVisitedRecords returns visited records sorted', () async {
      final now = DateTime.now();
      final older = Record(
        pictureId: 1, createdAt: now, updateAt: now, visitedAt: now.subtract(const Duration(days: 2)),
      );
      final newer = Record(
        pictureId: 2, createdAt: now, updateAt: now, visitedAt: now.subtract(const Duration(days: 1)),
      );
      await recordRepo.insert(older);
      await recordRepo.insert(newer);
      final results = await recordRepo.findVisitedRecords();
      expect(results.length, 2);
      expect(results.first.visitedAt!.millisecondsSinceEpoch,
          greaterThanOrEqualTo(results.last.visitedAt!.millisecondsSinceEpoch));
    });

    test('findVisitedRecords excludes records without visitedAt', () async {
      final visited = Record(pictureId: 1, createdAt: DateTime.now(), updateAt: DateTime.now(), visitedAt: DateTime.now());
      final notVisited = Record(pictureId: 2, createdAt: DateTime.now(), updateAt: DateTime.now());
      await recordRepo.insert(visited);
      await recordRepo.insert(notVisited);
      final results = await recordRepo.findVisitedRecords();
      expect(results.length, 1);
      expect(results.first.pictureId, 1);
    });

    test('findVisitedRecords respects limit', () async {
      for (int i = 0; i < 5; i++) {
        await recordRepo.insert(Record(
          pictureId: i, createdAt: DateTime.now(), updateAt: DateTime.now(), visitedAt: DateTime.now(),
        ));
      }
      final results = await recordRepo.findVisitedRecords(limit: 3);
      expect(results.length, 3);
    });

    test('paginate returns records ordered by createdAt desc', () async {
      final old = Record(pictureId: 1, createdAt: DateTime(2020), updateAt: DateTime(2020));
      final mid = Record(pictureId: 2, createdAt: DateTime(2021), updateAt: DateTime(2021));
      final recent = Record(pictureId: 3, createdAt: DateTime(2022), updateAt: DateTime(2022));
      await recordRepo.insert(old);
      await recordRepo.insert(mid);
      await recordRepo.insert(recent);
      final results = await recordRepo.paginate(limit: 10);
      expect(results.length, 3);
      expect(results[0].pictureId, 3);
      expect(results[1].pictureId, 2);
      expect(results[2].pictureId, 1);
    });

    test('paginate respects offset and limit', () async {
      for (int i = 0; i < 10; i++) {
        await recordRepo.insert(Record(
          pictureId: i, createdAt: DateTime(2020 + i), updateAt: DateTime(2020 + i),
        ));
      }
      final page1 = await recordRepo.paginate(offset: 0, limit: 3);
      expect(page1.length, 3);
      expect(page1[0].pictureId, 9);
      final page2 = await recordRepo.paginate(offset: 3, limit: 3);
      expect(page2.length, 3);
      expect(page2[0].pictureId, 6);
    });
  });
}
