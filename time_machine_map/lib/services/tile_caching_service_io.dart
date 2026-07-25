import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cachette/cachette.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TileCachingService {
  final _memoryCache = Cachette<String, ui.Image>(
    100,
    onEvict: (entry) => entry.value.dispose(),
  );

  TileCachingService({
    this.fileCacheMaximumSizeInBytes = 100 * 1024 * 1024,
    this.fileCacheTtl = const Duration(days: 30),
  });

  final int fileCacheMaximumSizeInBytes;
  final Duration fileCacheTtl;

  Directory? _cacheDir;
  int _writeCount = 0;
  static const int _cleanupInterval = 20;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) return _cacheDir!;
    final appCacheDir = await getApplicationCacheDirectory();
    final dirPath = p.join(appCacheDir.path, 'vector_tiles');
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  Future<ui.Image?> tileImage(String serverId, int z, int x, int y) async {
    final key = _tileKey(serverId, z, x, y);
    final cached = _memoryCache[key];
    if (cached != null) return cached;

    try {
      final file = await _tileFile(serverId, z, x, y);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          final image = frame.image;
          _memoryCache[key] = image;
          return image;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> storeTile(String serverId, int z, int x, int y, ui.Image image) async {
    _memoryCache[_tileKey(serverId, z, x, y)] = image;
    unawaited(_cacheToDisk(serverId, z, x, y, image));
  }

  Future<void> _cacheToDisk(String serverId, int z, int x, int y, ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = await _tileFile(serverId, z, x, y);
        await file.writeAsBytes(byteData.buffer.asUint8List());
        unawaited(_reportTileWritten());
      }
    } catch (_) {}
  }

  Future<bool> isTileCached(String serverId, int z, int x, int y) async {
    final key = _tileKey(serverId, z, x, y);
    if (_memoryCache.containsKey(key)) return true;
    try {
      final file = await _tileFile(serverId, z, x, y);
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<File> _tileFile(String serverId, int z, int x, int y) async {
    final cacheDir = await cacheDirectory;
    final safeId = serverId.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final dir = Directory('${cacheDir.path}/$safeId/$z/$x');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/$y.png');
  }

  Future<void> _reportTileWritten() async {
    if (++_writeCount >= _cleanupInterval) {
      _writeCount = 0;
      unawaited(_evict());
    }
  }

  Future<void> _evict() async {
    try {
      final dir = await cacheDirectory;
      final allFiles = <FileSystemEntity>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.png')) {
          allFiles.add(entity);
        }
      }
      if (allFiles.isEmpty) return;

      final now = DateTime.now();
      final remaining = <MapEntry<File, FileStat>>[];

      for (final entity in allFiles) {
        try {
          final file = entity as File;
          final stat = await file.stat();
          if (now.difference(stat.modified) > fileCacheTtl) {
            await file.delete();
          } else {
            remaining.add(MapEntry(file, stat));
          }
        } catch (_) {}
      }

      int totalSize = remaining.fold(0, (sum, e) => sum + e.value.size);
      if (totalSize > fileCacheMaximumSizeInBytes) {
        remaining.sort((a, b) => a.value.modified.compareTo(b.value.modified));
        for (final entry in remaining) {
          if (totalSize <= fileCacheMaximumSizeInBytes) break;
          try {
            await entry.key.delete();
            totalSize -= entry.value.size;
          } catch (_) {}
        }
      }

      await _cleanEmptyDirs(dir);
    } catch (e) {
      debugPrint('Tile cache eviction error: $e');
    }
  }

  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final dir = await cacheDirectory;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _cacheDir = null;
      _writeCount = 0;
    } catch (e) {
      debugPrint('Tile cache clear error: $e');
    }
  }

  Future<void> _cleanEmptyDirs(Directory dir) async {
    try {
      final entities = dir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is Directory) {
          await _cleanEmptyDirs(entity);
          try {
            if (entity.listSync().isEmpty) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static String _tileKey(String serverId, int z, int x, int y) =>
      '$serverId/$z/$x/$y';
}
