import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:time_machine_map/domain/vector_tile_style.dart';
import 'package:time_machine_map/services/vector_service.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// A [TileProvider] that renders vector tiles to images using
/// [VectorService] and the style loaded by [AdaptiveTileLayer].
class RenderedVectorTileProvider extends TileProvider {
  final String serverId;
  final VectorTileStyle style;
  final VectorService vectorService;
  final vtr.Theme theme;
  final vtr.SpriteIndex? spriteIndex;
  final ui.Image? spriteAtlas;
  final double scale;

  RenderedVectorTileProvider({
    required this.serverId,
    required this.style,
    required this.vectorService,
    required this.theme,
    this.spriteIndex,
    this.spriteAtlas,
    this.scale = 1.0,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _RenderedVectorTileImage(
      serverId: serverId,
      style: style,
      vectorService: vectorService,
      theme: theme,
      spriteIndex: spriteIndex,
      spriteAtlas: spriteAtlas,
      scale: scale,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
  }
}

class _RenderedVectorTileImage extends ImageProvider<_RenderedVectorTileImage> {
  final String serverId;
  final VectorTileStyle style;
  final VectorService vectorService;
  final vtr.Theme theme;
  final vtr.SpriteIndex? spriteIndex;
  final ui.Image? spriteAtlas;
  final double scale;
  final int z;
  final int x;
  final int y;

  _RenderedVectorTileImage({
    required this.serverId,
    required this.style,
    required this.vectorService,
    required this.theme,
    required this.spriteIndex,
    required this.spriteAtlas,
    required this.scale,
    required this.z,
    required this.x,
    required this.y,
  });

  String get _cacheServerId =>
      scale == 1.0 ? serverId : '$serverId@${scale.toStringAsFixed(2)}';

  @override
  Future<_RenderedVectorTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_RenderedVectorTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _RenderedVectorTileImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _load(decode),
      informationCollector: () => [
        DiagnosticsProperty<String>(
          'Tile',
          'z=$z, x=$x, y=$y',
          description: 'vector tile',
        ),
      ],
    );
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    try {
      final image = await vectorService.renderStyledTile(
        serverId: _cacheServerId,
        z: z,
        x: x,
        y: y,
        style: style,
        theme: theme,
        spriteIndex: spriteIndex,
        spriteAtlas: spriteAtlas,
        scale: scale,
      );
      // The image is owned by the tile cache, so hand the stream a clone that
      // it can dispose when the tile is no longer displayed.
      return ImageInfo(image: image.clone(), scale: 1.0);
    } catch (e, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: stackTrace,
        library: 'time_machine_map',
        context: ErrorDescription('while rendering vector tile $z/$x/$y'),
      ));
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        TileProvider.transparentImage,
      );
      final codec = await decode(buffer);
      try {
        final frame = await codec.getNextFrame();
        return ImageInfo(image: frame.image, scale: 1.0);
      } finally {
        codec.dispose();
      }
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _RenderedVectorTileImage &&
            serverId == other.serverId &&
            style == other.style &&
            vectorService == other.vectorService &&
            scale == other.scale &&
            z == other.z &&
            x == other.x &&
            y == other.y;
  }

  @override
  int get hashCode =>
      Object.hash(serverId, style, vectorService, scale, z, x, y);
}
