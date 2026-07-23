import 'package:flutter/foundation.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

import '../domain/vector_tile_style.dart';

Future<Uint8List> renderTileToBytes({
  required int z,
  required int x,
  required int y,
  required double zoom,
  required VectorTileStyle style,
}) async {
  final tileId = TileIdentity(z, x, y);
  final tilesBySource = <String, Tile>{};
  final theme = style.readTheme();
  final sprites = style.sprites;
  final vectorType = TileProviderType.vector.name.replaceAll('_', '-');

  for (final source in style.sources.entries) {
    final sourceName = source.key;
    try {
      if (source.value.type != vectorType) continue;

      final provider = NetworkVectorTileProvider(
        type: TileProviderType.vector,
        urlTemplate: source.value.urlTemplate,
        maximumZoom: source.value.maximumZoom,
        minimumZoom: source.value.minimumZoom,
      );
      final pbfBytes = await provider.provide(tileId);

      final vectorTile = VectorTileReader().read(pbfBytes);
      final tileData = TileFactory(theme, Logger.console()).createTileData(
        vectorTile,
      );
      tilesBySource[sourceName] = tileData.toTile();
    } catch (e) {
      debugPrint('Error processing source $sourceName: $e');
    }
  }

  final imageRender = ImageRenderer(theme: theme, scale: 1.0);
  final image = await imageRender.render(
    TileSource(
      tileset: Tileset(tilesBySource),
      spriteIndex: sprites?.readContent(),
      spriteAtlas: await sprites?.readImage(),
    ),
    zoom: zoom,
  );

  return image.toPng();
}
