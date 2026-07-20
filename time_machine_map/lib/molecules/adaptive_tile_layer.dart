import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_map_tiles/src/cache/cache.dart';
import 'package:vector_map_tiles/src/model/map_properties.dart';
import 'package:vector_map_tiles/src/widgets/map_layer.dart';
import 'package:vector_map_tiles/src/widgets/map_tiles_layer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

class AdaptiveTileLayer extends StatelessWidget {
  final TileProviders tileProviders;
  final Theme theme;
  final TileOffset tileOffset;
  final int concurrency;
  final Duration fileCacheTtl;
  final int fileCacheMaximumSizeInBytes;
  final Future<Directory> Function()? cacheFolder;

  const AdaptiveTileLayer({
    super.key,
    required this.tileProviders,
    required this.theme,
    required this.tileOffset,
    this.concurrency = 4,
    this.fileCacheTtl = const Duration(days: 30),
    this.fileCacheMaximumSizeInBytes = 50 * 1024 * 1024,
    this.cacheFolder,
  });

  MapProperties _createMapProperties() => MapProperties(
        tileProviders: tileProviders,
        theme: theme,
        tileOffset: tileOffset,
        concurrency: concurrency,
        cacheProperties: CacheProperties(
          fileCacheTtl: fileCacheTtl,
          fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
          cacheFolder: cacheFolder,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return MapLayer(mapProperties: _createMapProperties());
    }
    return MapTilesLayer(mapProperties: _createMapProperties());
  }
}
