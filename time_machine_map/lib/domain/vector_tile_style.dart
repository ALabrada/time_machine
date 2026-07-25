import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

class VectorTileStyle {
  final String? name;
  final Map<String, dynamic> theme;
  final Map<String, VectorTileSource> sources;
  final VectorSpriteStyle? sprites;
  final LatLng? center;
  final double? zoom;

  VectorTileStyle(
    {this.name,
      required this.theme,
      required this.sources,
      this.sprites,
      this.center,
      this.zoom,
    });
}

class VectorSpriteStyle {
  final Uint8List atlas;
  final Map<String, dynamic> content;

  VectorSpriteStyle({
    required this.atlas,
    required this.content,
  });
}

class VectorTileSource {
  final String type;
  final String urlTemplate;
  final int maximumZoom;
  final int minimumZoom;

  VectorTileSource({
    required this.type,
    required this.urlTemplate,
    required this.maximumZoom,
    required this.minimumZoom,
  });
}

extension StyleExtensions on VectorTileStyle {
  Theme readTheme() => ThemeReader().read(theme);

  Style toStyle() => Style(
    theme: readTheme(),
    providers: TileProviders({
      for (final entry in sources.entries)
        entry.key: NetworkVectorTileProvider(
          type: TileProviderType.values.firstWhere((v) => v.name == entry.value.type),
          urlTemplate: entry.value.urlTemplate,
          maximumZoom: entry.value.minimumZoom,
          minimumZoom: entry.value.maximumZoom,
        ),
    }),
    center: center,
    zoom: zoom,
    sprites: sprites == null ? null : SpriteStyle(
      atlasProvider: () async => sprites!.atlas,
      index: sprites!.readContent(),
    )
  );
}

extension SpriteExtensions on VectorSpriteStyle {
  SpriteIndex readContent() => SpriteIndexReader().read(content);

  Future<ui.Image> readImage() async {
    final codec = await ui.instantiateImageCodec(atlas);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}