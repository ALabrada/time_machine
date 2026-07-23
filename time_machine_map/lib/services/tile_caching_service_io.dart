import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TileCachingService {
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

  Future<XFile> tileFile(int z, int x, int y) async {
    final cacheDir = await cacheDirectory;
    final dir = Directory('${cacheDir.path}/$z/$x');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return XFile('${dir.path}/$y.png');
  }

  Future<bool> isTileCached(int z, int x, int y) async {
    final cacheDir = await cacheDirectory;
    final file = File('${cacheDir.path}/$z/$x/$y.png');
    return await file.exists() && await file.length() > 0;
  }

  Future<void> storeTile(int z, int x, int y, Uint8List bytes) async {
    final xfile = await tileFile(z, x, y);
    await File(xfile.path).writeAsBytes(bytes);
  }

  Future<void> reportTileWritten() async {
    if (++_writeCount >= _cleanupInterval) {
      _writeCount = 0;
      unawaited(evict());
    }
  }

  Future<void> evict() async {
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
}
