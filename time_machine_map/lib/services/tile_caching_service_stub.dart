import 'dart:ui' as ui;

import 'package:cachette/cachette.dart';

class TileCachingService {
  final _memoryCache = Cachette<String, ui.Image>(
    500,
    onEvict: (entry) => entry.value.dispose(),
  );

  TileCachingService({
    this.fileCacheMaximumSizeInBytes = 100 * 1024 * 1024,
    this.fileCacheTtl = const Duration(days: 30),
  });

  final int fileCacheMaximumSizeInBytes;
  final Duration fileCacheTtl;

  Future<ui.Image?> tileImage(String serverId, int z, int x, int y) async {
    return _memoryCache[_tileKey(serverId, z, x, y)];
  }

  Future<void> storeTile(String serverId, int z, int x, int y, ui.Image image) async {
    _memoryCache[_tileKey(serverId, z, x, y)] = image;
  }

  Future<bool> isTileCached(String serverId, int z, int x, int y) async {
    return _memoryCache.containsKey(_tileKey(serverId, z, x, y));
  }

  Future<void> clear() async {
    _memoryCache.clear();
  }

  static String _tileKey(String serverId, int z, int x, int y) =>
      '$serverId/$z/$x/$y';
}
