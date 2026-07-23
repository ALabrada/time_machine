import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

class TileCachingService {
  TileCachingService({
    this.fileCacheMaximumSizeInBytes = 100 * 1024 * 1024,
    this.fileCacheTtl = const Duration(days: 30),
  });

  final int fileCacheMaximumSizeInBytes;
  final Duration fileCacheTtl;

  final _cache = <String, Uint8List>{};
  int _writeCount = 0;
  static const int _cleanupInterval = 20;

  static const int _maxMemoryEntries = 200;

  Future<XFile> tileFile(int z, int x, int y) async {
    final key = _tileKey(z, x, y);
    final bytes = _cache[key];
    return XFile.fromData(bytes ?? Uint8List(0),
      name: 'tile_${z}_${x}_$y.png',
    );
  }

  Future<bool> isTileCached(int z, int x, int y) async {
    return _cache.containsKey(_tileKey(z, x, y));
  }

  Future<void> storeTile(int z, int x, int y, Uint8List bytes) async {
    _cache[_tileKey(z, x, y)] = bytes;
  }

  Future<void> reportTileWritten() async {
    if (++_writeCount >= _cleanupInterval) {
      _writeCount = 0;
      unawaited(evict());
    }
  }

  Future<void> evict() async {
    while (_cache.length > _maxMemoryEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> clear() async {
    _cache.clear();
    _writeCount = 0;
  }

  static String _tileKey(int z, int x, int y) => '$z/$x/$y';
}
