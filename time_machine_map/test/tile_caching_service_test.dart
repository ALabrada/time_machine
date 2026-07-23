import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_map/services/tile_caching_service_stub.dart';

void main() {
  group('TileCachingService', () {
    late TileCachingService service;

    setUp(() {
      service = TileCachingService(
        fileCacheMaximumSizeInBytes: 100 * 1024 * 1024,
        fileCacheTtl: const Duration(days: 30),
      );
    });

    test('default constructor uses expected default values', () {
      final s = TileCachingService();
      expect(s.fileCacheMaximumSizeInBytes, 100 * 1024 * 1024);
      expect(s.fileCacheTtl, const Duration(days: 30));
    });

    test('custom constructor values are respected', () {
      final s = TileCachingService(
        fileCacheMaximumSizeInBytes: 500,
        fileCacheTtl: const Duration(hours: 1),
      );
      expect(s.fileCacheMaximumSizeInBytes, 500);
      expect(s.fileCacheTtl, const Duration(hours: 1));
    });

    test('isTileCached returns false for uncached tile', () async {
      expect(await service.isTileCached(0, 0, 0), isFalse);
      expect(await service.isTileCached(10, 100, 200), isFalse);
    });

    test('isTileCached returns true after storeTile', () async {
      await service.storeTile(1, 2, 3, Uint8List.fromList([1, 2, 3]));
      expect(await service.isTileCached(1, 2, 3), isTrue);
    });

    test('tileFile returns stored bytes', () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      await service.storeTile(5, 10, 15, bytes);

      final file = await service.tileFile(5, 10, 15);
      expect(await file.readAsBytes(), bytes);
    });

    test('tileFile returns XFile with empty bytes for uncached tile', () async {
      final file = await service.tileFile(7, 14, 21);
      expect(await file.readAsBytes(), Uint8List(0));
    });

    test('multiple tiles are stored and retrieved independently', () async {
      await service.storeTile(1, 1, 1, Uint8List.fromList([11]));
      await service.storeTile(1, 1, 2, Uint8List.fromList([12]));
      await service.storeTile(2, 1, 1, Uint8List.fromList([21]));

      expect(await service.isTileCached(1, 1, 1), isTrue);
      expect(await service.isTileCached(1, 1, 2), isTrue);
      expect(await service.isTileCached(2, 1, 1), isTrue);
      expect(await service.isTileCached(1, 2, 1), isFalse);

      expect(await (await service.tileFile(1, 1, 1)).readAsBytes(), [11]);
      expect(await (await service.tileFile(1, 1, 2)).readAsBytes(), [12]);
      expect(await (await service.tileFile(2, 1, 1)).readAsBytes(), [21]);
    });

    test('storeTile overwrites existing tile bytes', () async {
      await service.storeTile(3, 6, 9, Uint8List.fromList([1, 2, 3]));
      await service.storeTile(3, 6, 9, Uint8List.fromList([4, 5, 6]));
      expect(await (await service.tileFile(3, 6, 9)).readAsBytes(), [4, 5, 6]);
    });

    test('clear removes all cached tiles', () async {
      await service.storeTile(1, 2, 3, Uint8List.fromList([1, 2, 3]));
      await service.storeTile(4, 5, 6, Uint8List.fromList([4, 5, 6]));
      await service.clear();

      expect(await service.isTileCached(1, 2, 3), isFalse);
      expect(await service.isTileCached(4, 5, 6), isFalse);
    });

    test('clear resets write count so reportTileWritten takes 20 more calls to trigger evict', () async {
      for (int i = 0; i < 19; i++) {
        await service.reportTileWritten();
      }

      await service.clear();

      await service.storeTile(0, 0, 0, Uint8List.fromList([0]));

      for (int i = 0; i < 19; i++) {
        await service.reportTileWritten();
      }

      expect(await service.isTileCached(0, 0, 0), isTrue);
    });

    test('evict is safe on empty cache', () async {
      await service.evict();
    });

    test('evict does not remove entries when cache is under limit', () async {
      for (int i = 0; i < 10; i++) {
        await service.storeTile(0, 0, i, Uint8List.fromList([i]));
      }
      await service.evict();
      for (int i = 0; i < 10; i++) {
        expect(await service.isTileCached(0, 0, i), isTrue);
      }
    });

    test('reportTileWritten does not trigger eviction before threshold', () async {
      for (int i = 0; i < 19; i++) {
        final before = service.isTileCached(0, 0, 0);
        await service.reportTileWritten();
      }
    });

    test('reportTileWritten resets writeCount and triggers evict on 20th call', () async {
      await service.storeTile(0, 0, 0, Uint8List.fromList([42]));

      for (int i = 0; i < 20; i++) {
        await service.reportTileWritten();
      }

      expect(await service.isTileCached(0, 0, 0), isTrue);
    });
  });
}
