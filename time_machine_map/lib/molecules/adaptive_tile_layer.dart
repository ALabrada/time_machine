import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_map/l10n/map_localizations.dart';
import 'package:time_machine_map/domain/vector_tile_style.dart';
import 'package:time_machine_map/services/vector_service.dart';
import 'package:time_machine_res/molecules/loading_container.dart';
import 'package:vector_map_tiles/src/cache/cache.dart';
import 'package:vector_map_tiles/src/model/map_properties.dart';
import 'package:vector_map_tiles/src/provider/network_vector_tile_provider.dart';
import 'package:vector_map_tiles/src/tile_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

import 'sprite_map_tiles_layer.dart';

class AdaptiveTileLayer extends StatelessWidget {
  final MapTileServer tileServer;
  final TileOffset tileOffset;
  final int concurrency;
  final Duration fileCacheTtl;
  final int fileCacheMaximumSizeInBytes;
  final Future<Directory> Function()? cacheFolder;
  final String userAgent;

  const AdaptiveTileLayer({
    super.key,
    required this.tileServer,
    required this.tileOffset,
    this.concurrency = 4,
    this.fileCacheTtl = const Duration(days: 30),
    this.fileCacheMaximumSizeInBytes = 50 * 1024 * 1024,
    this.cacheFolder,
    this.userAgent = 'com.example.app',
  });

  @override
  Widget build(BuildContext context) {
    final url = tileServer.url(context);
    if (tileServer.format == TileFormat.image) {
      return TileLayer(
        urlTemplate: url,
        userAgentPackageName: userAgent,
        tileProvider: CancellableNetworkTileProvider(),
        subdomains: tileServer.subdomains ?? const ['a', 'b', 'c'],
      );
    }
    final vectorService = context.read<VectorService>();
    return FutureBuilder<VectorTileStyle>(
      future: vectorService.loadStyle(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                MapLocalizations.of(context).tileLoadError,
                textAlign: TextAlign.center,
                style: TextTheme.of(context).labelLarge,
              ),
            ),
          );
        }
        final style = snapshot.data;
        if (style == null) {
          return const SizedBox.shrink();
        }
        return _VectorTileCanvasLayer(
          serverId: url,
          style: style,
          tileOffset: tileOffset,
          concurrency: concurrency,
          fileCacheTtl: fileCacheTtl,
          fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
          cacheFolder: cacheFolder,
          vectorService: vectorService,
        );
      },
    );
  }
}

class _VectorTileCanvasLayer extends StatelessWidget {
  final String serverId;
  final VectorTileStyle style;
  final TileOffset tileOffset;
  final int concurrency;
  final Duration fileCacheTtl;
  final int fileCacheMaximumSizeInBytes;
  final Future<Directory> Function()? cacheFolder;
  final VectorService vectorService;

  const _VectorTileCanvasLayer({
    required this.serverId,
    required this.style,
    required this.tileOffset,
    this.concurrency = 4,
    this.fileCacheTtl = const Duration(days: 30),
    this.fileCacheMaximumSizeInBytes = 50 * 1024 * 1024,
    this.cacheFolder,
    required this.vectorService,
  });

  Future<(SpriteIndex?, ui.Image?)> _loadSprites() async {
    final sprites = style.sprites;
    if (sprites == null) return (null, null);
    final index = sprites.readContent();
    final image = await sprites.readImage();
    return (index, image);
  }

  @override
  Widget build(BuildContext context) {
    final hasSprites = style.sprites != null;
    final future = hasSprites
        ? _loadSprites()
        : Future<(SpriteIndex?, ui.Image?)>.value((null, null));

    return FutureBuilder<(SpriteIndex?, ui.Image?)>(
      future: future,
      builder: (context, snapshot) {
        if (hasSprites && snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }

        final spriteIndex = snapshot.data?.$1;
        final spriteAtlas = snapshot.data?.$2;

        final theme = style.readTheme();
        final tileProviders = TileProviders({
          for (final entry in style.sources.entries)
            entry.key: NetworkVectorTileProvider(
              type: TileProviderType.values.firstWhere(
                (v) => v.name == entry.value.type,
              ),
              urlTemplate: entry.value.urlTemplate,
              maximumZoom: entry.value.maximumZoom,
              minimumZoom: entry.value.minimumZoom,
            ),
        });

        return MobileLayerTransformer(
          child: SpriteMapTilesLayer(
            serverId: serverId,
            mapProperties: MapProperties(
              tileProviders: tileProviders,
              theme: theme,
              tileOffset: tileOffset,
              concurrency: concurrency,
              cacheProperties: CacheProperties(
                fileCacheTtl: fileCacheTtl,
                fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
                cacheFolder: cacheFolder,
              ),
            ),
            spriteIndex: spriteIndex,
            spriteAtlas: spriteAtlas,
            vectorService: vectorService,
          ),
        );
      },
    );
  }
}
