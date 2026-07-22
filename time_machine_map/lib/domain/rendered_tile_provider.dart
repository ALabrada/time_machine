import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/vector_service.dart';

class RenderedVectorTileProvider extends TileProvider {
  final VectorService vectorService;
  final Map<String, dynamic> styleJson;
  final List<String> sourceNames;

  RenderedVectorTileProvider({
    required this.vectorService,
    required this.styleJson,
    required this.sourceNames,
  });

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      getImageWithCancelLoadingSupport(
        coordinates, options, Completer<void>().future,
      );

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    return _RenderedVectorTileImage(
      vectorService: vectorService,
      styleJson: styleJson,
      sourceNames: sourceNames,
      x: coordinates.x,
      y: coordinates.y,
      z: coordinates.z,
      cancelLoading: cancelLoading,
    );
  }
}

class _RenderedVectorTileImage
    extends ImageProvider<_RenderedVectorTileImage> {
  final VectorService vectorService;
  final Map<String, dynamic> styleJson;
  final List<String> sourceNames;
  final int x, y, z;
  final Future<void> cancelLoading;

  _RenderedVectorTileImage({
    required this.vectorService,
    required this.styleJson,
    required this.sourceNames,
    required this.x,
    required this.y,
    required this.z,
    required this.cancelLoading,
  });

  @override
  Future<_RenderedVectorTileImage> obtainKey(
      ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _RenderedVectorTileImage key,
    ImageDecoderCallback decode,
  ) {
    final canceller = TileRenderCanceller();
    unawaited(cancelLoading.then((_) => canceller.cancel()));
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode, canceller),
      scale: 1,
      debugLabel: 'vector_tile_$z/$x/$y',
    );
  }

  Future<ui.Codec> _load(
    _RenderedVectorTileImage key,
    ImageDecoderCallback decode,
    TileRenderCanceller canceller,
  ) async {
    try {
      final file = await vectorService.renderTile(
        z: z,
        x: x,
        y: y,
        zoom: z.toDouble(),
        sources: sourceNames,
        styleJson: styleJson,
        canceller: canceller,
      );
      return decode(
          await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
    } catch (e) {
      debugPrint('Error rendering tile $z/$x/$y: $e');
      return decode(
          await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _RenderedVectorTileImage &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          vectorService == other.vectorService;

  @override
  int get hashCode => Object.hash(vectorService, z, x, y);
}
