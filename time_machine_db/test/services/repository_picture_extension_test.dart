import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast.dart';

import 'package:time_machine_db/time_machine_db.dart';

void main() {
  group('PictureRepository extension', () {
    late Database db;
    late Repository<Picture> picRepo;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('test_pic_ext_${DateTime.now().millisecondsSinceEpoch}.db');
      picRepo = Repository<Picture>.create(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('findPictureByIdAndProvider finds matching picture', () async {
      final pic1 = Picture(id: 'ext_1', url: 'url_1', latitude: 0, longitude: 0, provider: 'pastvu');
      final pic2 = Picture(id: 'ext_2', url: 'url_2', latitude: 0, longitude: 0, provider: 'retro');
      await picRepo.insert(pic1);
      await picRepo.insert(pic2);
      final result = await picRepo.findPictureByIdAndProvider('ext_1', 'pastvu');
      expect(result, isNotNull);
      expect(result!.id, 'ext_1');
    });

    test('findPictureByIdAndProvider returns null when not found', () async {
      final result = await picRepo.findPictureByIdAndProvider('nonexistent', 'pastvu');
      expect(result, isNull);
    });

    test('findPictureByIdAndProvider requires both id and provider match', () async {
      final pic = Picture(id: 'shared', url: 'url', latitude: 0, longitude: 0, provider: 'pastvu');
      await picRepo.insert(pic);
      final result = await picRepo.findPictureByIdAndProvider('shared', 'retro');
      expect(result, isNull);
    });

    test('findPicturesWithText filters by keywords', () async {
      final pic1 = Picture(id: 't1', url: 'u1', latitude: 0, longitude: 0, description: 'Moscow Red Square');
      final pic2 = Picture(id: 't2', url: 'u2', latitude: 0, longitude: 0, description: 'Paris Eiffel Tower');
      await picRepo.insert(pic1);
      await picRepo.insert(pic2);
      final results = await picRepo.findPicturesWithText(['Moscow']);
      expect(results.length, 1);
      expect(results.first.id, 't1');
    });

    test('findPicturesWithText filters by providers', () async {
      final pic1 = Picture(id: 'p1', url: 'u1', latitude: 0, longitude: 0, description: 'photo', provider: 'pastvu');
      final pic2 = Picture(id: 'p2', url: 'u2', latitude: 0, longitude: 0, description: 'photo', provider: 'retro');
      await picRepo.insert(pic1);
      await picRepo.insert(pic2);
      final results = await picRepo.findPicturesWithText(['photo'], providers: ['pastvu']);
      expect(results.length, 1);
      expect(results.first.provider, 'pastvu');
    });

    test('findVisitedPictures returns visited pictures sorted', () async {
      final now = DateTime.now();
      final older = Picture(
        id: 'v1', url: 'u1', latitude: 0, longitude: 0,
        visitedAt: now.subtract(const Duration(days: 5)),
      );
      final newer = Picture(
        id: 'v2', url: 'u2', latitude: 0, longitude: 0,
        visitedAt: now.subtract(const Duration(days: 1)),
      );
      await picRepo.insert(older);
      await picRepo.insert(newer);
      final results = await picRepo.findVisitedPictures();
      expect(results.length, 2);
      expect(results.first.id, 'v2');
    });

    test('findVisitedPictures excludes unvisited', () async {
      final visited = Picture(id: 'v3', url: 'u3', latitude: 0, longitude: 0, visitedAt: DateTime.now());
      final notVisited = Picture(id: 'v4', url: 'u4', latitude: 0, longitude: 0);
      await picRepo.insert(visited);
      await picRepo.insert(notVisited);
      final results = await picRepo.findVisitedPictures();
      expect(results.length, 1);
      expect(results.first.id, 'v3');
    });

    test('findVisitedPictures filters by providers', () async {
      final pic1 = Picture(
        id: 'vp1', url: 'u1', latitude: 0, longitude: 0,
        provider: 'pastvu', visitedAt: DateTime.now(),
      );
      final pic2 = Picture(
        id: 'vp2', url: 'u2', latitude: 0, longitude: 0,
        provider: 'retro', visitedAt: DateTime.now(),
      );
      await picRepo.insert(pic1);
      await picRepo.insert(pic2);
      final results = await picRepo.findVisitedPictures(providers: ['pastvu']);
      expect(results.length, 1);
      expect(results.first.provider, 'pastvu');
    });
  });
}
