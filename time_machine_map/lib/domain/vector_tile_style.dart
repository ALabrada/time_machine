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

/// Recursively replace unsupported expressions in JSON.
/// Converts [boolean, input, fallback] → input
/// Converts [feature-state, prop] → [get, prop]
/// Converts [interpolate, [exponential, base], ...] → [interpolate, [linear], ...]
///   when stop outputs are color strings (exponential doesn't handle non-numeric outputs).
dynamic _patchUnsupported(dynamic node) {
  if (node is List) {
    if (node.isNotEmpty && node[0] == 'boolean' && node.length == 3) {
      return _patchUnsupported(node[1]);
    }
    if (node.isNotEmpty && node[0] == 'feature-state' && node.length == 2) {
      return ['get', _patchUnsupported(node[1])];
    }
    if (node.length >= 4 &&
        node[0] == 'interpolate' &&
        node[1] is List &&
        node[1].length >= 2 &&
        node[1][0] == 'exponential' &&
        _hasColorOutputs(node)) {
      final patched = [...node];
      patched[1] = ['linear'];
      return patched.map(_patchUnsupported).toList(growable: false);
    }
    return node.map(_patchUnsupported).toList(growable: false);
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _patchUnsupported(v)));
  }
  return node;
}

bool _hasColorOutputs(List node) {
  for (int i = 3; i + 1 < node.length; i += 2) {
    final output = node[i + 1];
    if (output is String && _isColorString(output)) return true;
  }
  return false;
}

bool _isColorString(String s) {
  return s.startsWith('#') || s.startsWith('rgb') || s.startsWith('hsl');
}


extension StyleExtensions on VectorTileStyle {
  Theme readTheme() {
    // Patch style JSON: replace unsupported boolean & feature-state expressions
    final patched = Map<String, dynamic>.from(theme);
    patched['layers'] = (patched['layers'] as List<dynamic>)
        .map((layer) {
          var patched = _patchUnsupported(layer);
          if (patched is Map<String, dynamic>) {
            // Ensure all symbol layers have a paint section
            if (patched['type'] == 'symbol' && patched['paint'] == null) {
              patched['paint'] = <String, dynamic>{};
            }
            // FillRenderer doesn't convert pixel widths to tile space,
            // so the default 0.1 tile-unit outline width (~0.006px) is invisible.
            // Set to 16 tile units (~1px at 256/4096) when outline color exists.
            if (patched['type'] == 'fill' && patched['paint'] is Map) {
              final paint = patched['paint'] as Map;
              if (paint['fill-outline-color'] != null &&
                  paint['fill-outline-width'] == null) {
                paint['fill-outline-width'] = 16;
              }
            }
          }
          return patched;
        })
        .toList(growable: false);
    return ThemeReader().read(patched);
  }

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
    if (atlas.isEmpty) {
      throw Exception('Sprite atlas is empty');
    }
    final codec = await ui.instantiateImageCodec(atlas);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}