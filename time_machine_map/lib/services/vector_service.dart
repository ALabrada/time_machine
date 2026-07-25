import 'dart:async';
import 'dart:ui' as ui;

import 'package:cachette/cachette.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles/src/style/uri_mapper.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../domain/vector_tile_style.dart';
import 'tile_caching_service.dart';

class VectorService {
  final Dio dio;
  final String vkApiKey;
  final _styleCache = <String, VectorTileStyle>{};
  final TileCachingService cachingService;
  final _tileImageCache = Cachette<String, ui.Image>(
    100,
    onEvict: (entry) => entry.value.dispose(),
  );

  VectorService({
    required this.vkApiKey,
    String? userAgent,
    TileCachingService? cachingService,
    int fileCacheMaximumSizeInBytes = 100 * 1024 * 1024,
    Duration fileCacheTtl = const Duration(days: 30),
  }) : dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      if (userAgent != null)
        'User-Agent': userAgent,
    },
  )),
       cachingService = cachingService ?? TileCachingService(
         fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
         fileCacheTtl: fileCacheTtl,
       ) {
    if (!kReleaseMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestBody: true,
          responseBody: true,
          error: true,
          logPrint: (o) => debugPrint(o.toString()),
        ),
      );
    }
  }

  void clearStyleCache() {
    _styleCache.clear();
  }

  Future<VectorTileStyle> loadStyle(String uri) async {
    final cached = _styleCache[uri];
    if (cached != null) return cached;
    final uriMapper = ExtendedStyleUriMapper(key: vkApiKey);
    final url = uriMapper.map(uri);
    final response = await dio.get(url);
    final styleJson = response.data as Map<String, dynamic>;
    final sources = styleJson['sources'];
    if (sources is! Map) {
      throw _invalidStyle(url);
    }
    final sourcesByName = await _readSources(sources, uri);
    final name = styleJson['name'] as String?;

    final center = styleJson['center'];
    LatLng? centerPoint;
    if (center is List && center.length == 2) {
      centerPoint =
          LatLng((center[1] as num).toDouble(), (center[0] as num).toDouble());
    }
    double? zoom = (styleJson['zoom'] as num?)?.toDouble();
    if (zoom != null && zoom < 2) {
      zoom = null;
      centerPoint = null;
    }
    final spriteUri = styleJson['sprite'];
    VectorSpriteStyle? sprites;
    if (spriteUri is String && spriteUri.trim().isNotEmpty) {
      final spriteUris = uriMapper.mapSprite(uri, spriteUri);
      for (final spriteUri in spriteUris) {
        dynamic spritesJson;
        Uint8List spritesImage;
        try {
          final spritesResponse = await dio.get(spriteUri.json);
          spritesJson = spritesResponse.data;

          final imageResponse = await dio.get(
            spriteUri.image,
            options: Options(responseType: ResponseType.bytes),
          );
          spritesImage = imageResponse.data;
        } catch (e) {
          debugPrint('error reading sprite uri: ${spriteUri.json}');
          continue;
        }

        sprites = VectorSpriteStyle(atlas: spritesImage, content: spritesJson);
        break;
      }
    }
    final result = VectorTileStyle(
      theme: styleJson,
      sources: sourcesByName,
      sprites: sprites,
      name: name,
      center: centerPoint,
      zoom: zoom,
    );
    _styleCache[uri] = result;
    return result;
  }

  Future<Map<String, VectorTileSource>> _readSources(Map sources, String uri) async {
    final sourceEntries = await Stream.fromIterable(sources.entries)
      .asyncMap((entry) async {
        final sourceType = entry.value['type'];
        dynamic source;
        var entryUrl = entry.value['url'] as String?;
        if (entryUrl != null) {
          final sourceUrl = ExtendedStyleUriMapper(key: vkApiKey).mapSource(uri, entryUrl);
          final response = await dio.get(sourceUrl);
          source = response.data;
          if (source is! Map) {
            throw _invalidStyle(sourceUrl);
          }
        } else {
          source = entry.value;
        }
        final entryTiles = source['tiles'];
        final maxzoom = source['maxzoom'] as int? ?? 14;
        final minzoom = source['minzoom'] as int? ?? 1;
        if (entryTiles is List && entryTiles.isNotEmpty) {
          final tileUri = entryTiles[0] as String;
          final tileUrl = ExtendedStyleUriMapper(key: vkApiKey).mapTiles(tileUri);
          final source = VectorTileSource(
            type: sourceType,
            urlTemplate: tileUrl,
            maximumZoom: maxzoom,
            minimumZoom: minzoom,
          );
          return MapEntry(entry.key, source);
        }
        return null;
      })
      .where((e) => e != null)
      .toList();
    if (sourceEntries.isEmpty) {
      throw 'Unexpected response';
    }
    return Map.fromEntries(
      sourceEntries.nonNulls.map((e) => MapEntry<String, VectorTileSource>(e.key as String, e.value)),
    );
  }

  Future<ui.Image> renderTileImage({
    required int z,
    required int x,
    required int y,
    required Theme theme,
    required Tileset tileset,
    required RasterTileset rasterTileset,
    SpriteIndex? spriteIndex,
    ui.Image? spriteAtlas,
  }) async {
    final key = '$z/$x/$y';

    final cached = _tileImageCache[key];
    if (cached != null) return cached;

    final diskCached = await cachingService.isTileCached(z, x, y);
    if (diskCached) {
      try {
        final xfile = await cachingService.tileFile(z, x, y);
        final bytes = await xfile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        final image = frame.image;
        _tileImageCache[key] = image;
        return image;
      } catch (_) {}
    }

    final renderer = ImageRenderer(theme: theme, scale: 1.0);
    final image = await renderer.render(
      TileSource(
        tileset: tileset,
        rasterTileset: rasterTileset,
        spriteIndex: spriteIndex,
        spriteAtlas: spriteAtlas,
      ),
      zoom: z.toDouble(),
    );

    _tileImageCache[key] = image;
    unawaited(_cacheTileImage(z, x, y, image));

    return image;
  }

  Future<void> _cacheTileImage(int z, int x, int y, ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await cachingService.storeTile(
          z, x, y, byteData.buffer.asUint8List(),
        );
      }
    } catch (_) {}
  }
}

String _invalidStyle(String url) =>
    'Uri does not appear to be a valid style: $url';

class ExtendedStyleUriMapper extends StyleUriMapper {
  static const vkScheme = 'mmr';
  final String _key;

  ExtendedStyleUriMapper({required String key}) : _key = key, super(key: key);

  @override
  String map(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == vkScheme) {
      return _toVKUri(_authenticate(parsed));
    }
    return super.map(uri);
  }

  @override
  String mapSource(String styleUri, String sourceUri) {
    final parsed = Uri.parse(sourceUri);
    if (parsed.scheme == vkScheme) {
      return _toVKUri(_authenticate(parsed, timestamp: true));
    }
    return super.mapSource(styleUri, sourceUri);
  }

  @override
  List<SpriteUri> mapSprite(String styleUri, String spriteUri) {
    final parsed = Uri.parse(spriteUri);
    if (parsed.scheme == vkScheme) {
      final jsonUri = parsed.replace(path: '${parsed.path}.json');
      final imageUri = parsed.replace(path: '${parsed.path}.png');
      return [SpriteUri(
        json: _toVKUri(_authenticate(jsonUri, timestamp: true)),
        image: _toVKUri(_authenticate(imageUri, timestamp: true)),
      )];
    }
    return super.mapSprite(styleUri, spriteUri);
  }

  @override
  String mapTiles(String tileUri) {
    final mapped = tileUri.replaceFirst('$vkScheme://', 'https://tiles.maps.vk.com/');
    return _authenticateString(mapped);
  }

  String _toVKUri(String source) => source.replaceFirst('$vkScheme://', 'https://maps.vk.com/');

  String _authenticateString(String url, {bool timestamp = false}) {
    final buffer = StringBuffer(url);
    buffer.write(url.contains('?') ? '&' : '?');
    buffer.write('api_key=$_key');
    if (timestamp) {
      buffer.write('&t=${DateTime.now().toUtc().millisecondsSinceEpoch}');
    }
    return buffer.toString();
  }

  String _authenticate(Uri source, {bool timestamp = false}) {
    final query = Map<String, String>.from(source.queryParameters);
    query['api_key'] = _key;
    if (timestamp) {
      query['t'] = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    }
    return source.replace(queryParameters: query).toString();
  }
}

class StyleWithRaw {
  final Style style;
  final Map<String, dynamic> raw;

  StyleWithRaw({required this.style, required this.raw});
}