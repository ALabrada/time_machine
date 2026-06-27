import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart' as sembast;

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('Repository CRUD operations', () {
    late Database db;
    late Repository<Picture> pictureRepo;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_crud_${DateTime.now().millisecondsSinceEpoch}.db');
      pictureRepo = Repository<Picture>.create(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insert adds entity and assigns localId', () async {
      final picture = Picture(
        id: 'pic_001',
        url: 'https://example.com/photo.jpg',
        latitude: 55.7558,
        longitude: 37.6173,
      );
      final inserted = await pictureRepo.insert(picture);
      expect(inserted.localId, isNotNull);
      expect(inserted.localId, greaterThan(0));
    });

    test('getById retrieves inserted entity', () async {
      final picture = Picture(
        id: 'pic_002',
        url: 'https://example.com/photo2.jpg',
        latitude: 48.8566,
        longitude: 2.3522,
      );
      final inserted = await pictureRepo.insert(picture);
      final retrieved = await pictureRepo.getById(inserted.localId!);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'pic_002');
      expect(retrieved.url, 'https://example.com/photo2.jpg');
    });

    test('getById returns null for non-existent id', () async {
      final result = await pictureRepo.getById(99999);
      expect(result, isNull);
    });

    test('update modifies existing entity', () async {
      final picture = Picture(
        id: 'pic_003',
        url: 'https://example.com/photo3.jpg',
        latitude: 55.7558,
        longitude: 37.6173,
        description: 'Original description',
      );
      final inserted = await pictureRepo.insert(picture);
      inserted.description = 'Updated description';
      await pictureRepo.update(inserted);
      final retrieved = await pictureRepo.getById(inserted.localId!);
      expect(retrieved!.description, 'Updated description');
    });

    test('delete removes entity', () async {
      final picture = Picture(
        id: 'pic_004',
        url: 'https://example.com/photo4.jpg',
        latitude: 40.7128,
        longitude: -74.0060,
      );
      final inserted = await pictureRepo.insert(picture);
      await pictureRepo.delete(inserted.localId!);
      final retrieved = await pictureRepo.getById(inserted.localId!);
      expect(retrieved, isNull);
    });

    test('delete returns false for non-existent id', () async {
      final result = await pictureRepo.delete(99999);
      expect(result, isFalse);
    });

    test('list returns all entities', () async {
      final pic1 = Picture(id: 'pic_a', url: 'url_a', latitude: 0, longitude: 0);
      final pic2 = Picture(id: 'pic_b', url: 'url_b', latitude: 0, longitude: 0);
      final pic3 = Picture(id: 'pic_c', url: 'url_c', latitude: 0, longitude: 0);
      await pictureRepo.insert(pic1);
      await pictureRepo.insert(pic2);
      await pictureRepo.insert(pic3);
      final all = await pictureRepo.list();
      expect(all.length, 3);
    });

    test('list returns empty list when no entities', () async {
      final all = await pictureRepo.list();
      expect(all, isEmpty);
    });

    test('find with Finder filters results', () async {
      final pic1 = Picture(id: 'a', url: 'url_a', latitude: 0, longitude: 0, provider: 'pastvu');
      final pic2 = Picture(id: 'b', url: 'url_b', latitude: 0, longitude: 0, provider: 'retro');
      await pictureRepo.insert(pic1);
      await pictureRepo.insert(pic2);
      final finder = sembast.Finder(filter: sembast.Filter.equals('provider', 'pastvu'));
      final results = await pictureRepo.find(finder);
      expect(results.length, 1);
      expect(results.first.id, 'a');
    });

    test('findFirst returns first match', () async {
      final pic1 = Picture(id: 'x', url: 'url_x', latitude: 0, longitude: 0, provider: 'test');
      final pic2 = Picture(id: 'y', url: 'url_y', latitude: 0, longitude: 0, provider: 'test');
      await pictureRepo.insert(pic1);
      await pictureRepo.insert(pic2);
      final finder = sembast.Finder(filter: sembast.Filter.equals('provider', 'test'));
      final result = await pictureRepo.findFirst(finder);
      expect(result, isNotNull);
      expect(result!.id, 'x');
    });

    test('findFirst returns null when no match', () async {
      final finder = sembast.Finder(filter: sembast.Filter.equals('id', 'non_existent'));
      final result = await pictureRepo.findFirst(finder);
      expect(result, isNull);
    });

    test('upsert inserts new entity without localId', () async {
      final picture = Picture(
        id: 'new_pic',
        url: 'url_new',
        latitude: 10,
        longitude: 20,
      );
      final result = await pictureRepo.upsert(picture);
      expect(result.localId, isNotNull);
      final all = await pictureRepo.list();
      expect(all.length, 1);
    });

    test('upsert updates existing entity with localId', () async {
      final picture = Picture(
        id: 'existing',
        url: 'url_original',
        latitude: 10,
        longitude: 20,
      );
      final inserted = await pictureRepo.insert(picture);
      inserted.url = 'url_updated';
      final result = await pictureRepo.upsert(inserted);
      expect(result.localId, inserted.localId);
      final retrieved = await pictureRepo.getById(inserted.localId!);
      expect(retrieved!.url, 'url_updated');
    });
  });
}
