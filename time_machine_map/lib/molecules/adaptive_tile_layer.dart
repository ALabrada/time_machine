import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
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
    if (tileServer.format == TileFormat.image) {
      return TileLayer(
        urlTemplate: tileServer.url,
        userAgentPackageName: userAgent,
        tileProvider: CancellableNetworkTileProvider(),
        subdomains: tileServer.subdomains ?? const ['a', 'b', 'c'],
      );
    }
    final vectorService = context.read<VectorService>();
    return FutureBuilder<VectorTileStyle>(
      future: vectorService.loadStyle(tileServer.url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        final style = snapshot.data;
        if (style == null) {
          return const SizedBox.shrink();
        }
        return _VectorTileCanvasLayer(
          serverId: tileServer.url,
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

class _VectorTileCanvasLayer extends StatefulWidget {
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

  @override
  State<_VectorTileCanvasLayer> createState() => _VectorTileCanvasLayerState();
}

class _VectorTileCanvasLayerState extends State<_VectorTileCanvasLayer> {
  SpriteIndex? _spriteIndex;
  ui.Image? _spriteAtlas;
  bool _loadingSprites = true;

  @override
  void initState() {
    super.initState();
    _loadSprites();
  }

  @override
  void didUpdateWidget(covariant _VectorTileCanvasLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _loadingSprites = true;
      _loadSprites();
    }
  }

  Future<void> _loadSprites() async {
    final sprites = widget.style.sprites;
    if (sprites != null) {
      try {
        final index = sprites.readContent();
        final image = await sprites.readImage();
        if (mounted) {
          setState(() {
            _spriteIndex = index;
            _spriteAtlas = image;
            _loadingSprites = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loadingSprites = false);
        }
      }
    } else {
      if (mounted) setState(() => _loadingSprites = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSprites) {
      return const LoadingView();
    }
    final theme = widget.style.readTheme();
    final tileProviders = TileProviders({
      for (final entry in widget.style.sources.entries)
        entry.key: NetworkVectorTileProvider(
          type: TileProviderType.values.firstWhere(
            (v) => v.name == entry.value.type,
          ),
          urlTemplate: entry.value.urlTemplate,
          maximumZoom: entry.value.maximumZoom,
          minimumZoom: entry.value.minimumZoom,
        ),
    });
    return SpriteMapTilesLayer(
      serverId: widget.serverId,
      mapProperties: MapProperties(
        tileProviders: tileProviders,
        theme: theme,
        tileOffset: widget.tileOffset,
        concurrency: widget.concurrency,
        cacheProperties: CacheProperties(
          fileCacheTtl: widget.fileCacheTtl,
          fileCacheMaximumSizeInBytes: widget.fileCacheMaximumSizeInBytes,
          cacheFolder: widget.cacheFolder,
        ),
      ),
      spriteIndex: _spriteIndex,
      spriteAtlas: _spriteAtlas,
      vectorService: widget.vectorService,
    );
  }
}
