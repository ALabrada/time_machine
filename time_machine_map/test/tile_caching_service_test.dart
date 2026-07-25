import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_map/services/tile_caching_service_stub.dart';

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return image;
}

void main() {
  group('TileCachingService', () {
    late TileCachingService service;
    const serverId = 'test_server';

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
      expect(await service.isTileCached(serverId, 0, 0, 0), isFalse);
      expect(await service.isTileCached(serverId, 10, 100, 200), isFalse);
    });

    test('isTileCached returns true after storeTile', () async {
      final image = await _createTestImage();
      await service.storeTile(serverId, 1, 2, 3, image);
      expect(await service.isTileCached(serverId, 1, 2, 3), isTrue);
      image.dispose();
    });

    test('tileImage returns null for uncached tile', () async {
      expect(await service.tileImage(serverId, 7, 14, 21), isNull);
    });

    test('tileImage returns stored image', () async {
      final image = await _createTestImage();
      await service.storeTile(serverId, 5, 10, 15, image);

      final result = await service.tileImage(serverId, 5, 10, 15);
      expect(result, isA<ui.Image>());
      expect(result, same(image));
    });

    test('multiple tiles are stored and retrieved independently', () async {
      final image1 = await _createTestImage();
      final image2 = await _createTestImage();
      final image3 = await _createTestImage();

      await service.storeTile(serverId, 1, 1, 1, image1);
      await service.storeTile(serverId, 1, 1, 2, image2);
      await service.storeTile(serverId, 2, 1, 1, image3);

      expect(await service.isTileCached(serverId, 1, 1, 1), isTrue);
      expect(await service.isTileCached(serverId, 1, 1, 2), isTrue);
      expect(await service.isTileCached(serverId, 2, 1, 1), isTrue);
      expect(await service.isTileCached(serverId, 1, 2, 1), isFalse);

      expect(await service.tileImage(serverId, 1, 1, 1), same(image1));
      expect(await service.tileImage(serverId, 1, 1, 2), same(image2));
      expect(await service.tileImage(serverId, 2, 1, 1), same(image3));

      image1.dispose();
      image2.dispose();
      image3.dispose();
    });

    test('storeTile overwrites existing tile', () async {
      final image1 = await _createTestImage();
      final image2 = await _createTestImage();

      await service.storeTile(serverId, 3, 6, 9, image1);
      await service.storeTile(serverId, 3, 6, 9, image2);

      expect(await service.tileImage(serverId, 3, 6, 9), same(image2));

      image1.dispose();
      image2.dispose();
    });

    test('clear removes all cached tiles', () async {
      final image1 = await _createTestImage();
      final image2 = await _createTestImage();

      await service.storeTile(serverId, 1, 2, 3, image1);
      await service.storeTile(serverId, 4, 5, 6, image2);
      await service.clear();

      expect(await service.isTileCached(serverId, 1, 2, 3), isFalse);
      expect(await service.isTileCached(serverId, 4, 5, 6), isFalse);

      image1.dispose();
      image2.dispose();
    });

    test('different server IDs are stored separately', () async {
      final imageA = await _createTestImage();
      final imageB = await _createTestImage();

      await service.storeTile('server_a', 1, 2, 3, imageA);
      await service.storeTile('server_b', 1, 2, 3, imageB);

      expect(await service.tileImage('server_a', 1, 2, 3), same(imageA));
      expect(await service.tileImage('server_b', 1, 2, 3), same(imageB));

      imageA.dispose();
      imageB.dispose();
    });
  });
}
