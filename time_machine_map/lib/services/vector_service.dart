import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../domain/vector_tile_style.dart';
import 'tile_caching_service.dart';

class VectorService {
  final Dio dio;
  final String vkApiKey;
  final _styleCache = <String, VectorTileStyle>{};
  final TileCachingService cachingService;

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
        final maxzoom = (source['maxzoom'] as num?)?.toInt() ?? 14;
        final minzoom = (source['minzoom'] as num?)?.toInt() ?? 1;
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

  /// Loads the source tiles for [style] and renders the tile at [z]/[x]/[y].
  ///
  /// Sources are fetched at their native maximum zoom and translated to the
  /// requested zoom when necessary.
  Future<ui.Image> renderStyledTile({
    required String serverId,
    required int z,
    required int x,
    required int y,
    required VectorTileStyle style,
    required Theme theme,
    SpriteIndex? spriteIndex,
    ui.Image? spriteAtlas,
    double scale = 1.0,
  }) async {
    final cached = await cachingService.tileImage(serverId, z, x, y);
    if (cached != null) return cached;

    final tilesBySource = <String, Tile>{};
    final rasterTiles = <String, RasterTile>{};
    final rasterTileset = RasterTileset(tiles: rasterTiles);
    final sources = style.sources.entries
        .where((entry) => theme.tileSources.contains(entry.key))
        .toList(growable: false);

    try {
      final results = await Future.wait(sources.map((entry) => _loadSourceTile(
            name: entry.key,
            source: entry.value,
            z: z,
            x: x,
            y: y,
            theme: theme,
            tiles: tilesBySource,
            rasters: rasterTiles,
          )));

      final renderer = ImageRenderer(theme: theme, scale: scale);
      final image = await renderer.render(
        TileSource(
          tileset: Tileset(tilesBySource),
          rasterTileset: rasterTileset,
          spriteIndex: spriteIndex,
          spriteAtlas: spriteAtlas,
        ),
        zoom: z.toDouble(),
      );

      // Avoid persisting a partial/blank tile if a source failed for a reason
      // that may be transient (e.g. a network error).
      if (!results.contains(false)) {
        unawaited(cachingService.storeTile(serverId, z, x, y, image));
      }
      return image;
    } finally {
      rasterTileset.dispose();
    }
  }

  Future<bool> _loadSourceTile({
    required String name,
    required VectorTileSource source,
    required int z,
    required int x,
    required int y,
    required Theme theme,
    required Map<String, Tile> tiles,
    required Map<String, RasterTile> rasters,
  }) async {
    if (z < source.minimumZoom) return true;

    final translation = _TileTranslation.forZoom(z, x, y, source.maximumZoom);
    final url = _tileUrl(
      source.urlTemplate,
      translation.translatedZ,
      translation.translatedX,
      translation.translatedY,
    );

    try {
      final bytes = await _fetchTile(url);
      if (source.type == 'vector') {
        final vectorTile = VectorTileReader().read(bytes);
        var tileData =
            TileFactory(theme, const Logger.noop()).createTileData(vectorTile);
        if (translation.isTranslated) {
          tileData = _translateTileData(tileData, translation);
        }
        tiles[name] = tileData.toTile();
      } else if (source.type == 'raster' || source.type == 'raster-dem') {
        final image = await _decodeImage(bytes);
        var scope = ui.Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
        if (translation.isTranslated) {
          scope = _translatedScope(scope, translation);
        }
        rasters[name] = RasterTile(image: image, scope: scope);
      }
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 204) {
        return true;
      }
      debugPrint('Error loading source $name for tile $z/$x/$y: $e');
      return false;
    } catch (e) {
      debugPrint('Error loading source $name for tile $z/$x/$y: $e');
      return false;
    }
  }

  Future<Uint8List> _fetchTile(String url) async {
    final response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Empty response for $url');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  String _tileUrl(String template, int z, int x, int y) {
    return template.replaceAllMapped(RegExp(r'\{(x|y|z)\}'), (match) {
      switch (match.group(1)) {
        case 'x':
          return x.toString();
        case 'y':
          return y.toString();
        case 'z':
          return z.toString();
        default:
          throw Exception('unsupported tile URL token: ${match.group(1)}');
      }
    });
  }

  Future<ui.Image> renderTileImage({
    required String serverId,
    required int z,
    required int x,
    required int y,
    required Theme theme,
    required Tileset tileset,
    required RasterTileset rasterTileset,
    SpriteIndex? spriteIndex,
    ui.Image? spriteAtlas,
    double scale = 1.0,
  }) async {
    final cached = await cachingService.tileImage(serverId, z, x, y);
    if (cached != null) return cached;

    final renderer = ImageRenderer(theme: theme, scale: scale);
    final image = await renderer.render(
      TileSource(
        tileset: tileset,
        rasterTileset: rasterTileset,
        spriteIndex: spriteIndex,
        spriteAtlas: spriteAtlas,
      ),
      zoom: z.toDouble(),
    );

    unawaited(cachingService.storeTile(serverId, z, x, y, image));
    return image;
  }
}

TileData _translateTileData(TileData tileData, _TileTranslation translation) {
  const tileSize = 256.0;
  final clipSize = tileSize / translation.fraction;
  final paddingSize = clipSize * 0.25;
  final halfPaddingSize = paddingSize / 2;
  final totalSize = clipSize + paddingSize;
  final dx = (translation.xOffset * clipSize) - halfPaddingSize;
  final dy = (translation.yOffset * clipSize) - halfPaddingSize;
  final clip = math.Rectangle<double>(dx, dy, totalSize, totalSize);
  final clipped = TileClip(bounds: clip).clip(tileData);
  return TileTranslate(
    math.Point<double>(-clip.left - halfPaddingSize, -clip.top - halfPaddingSize),
    scale: translation.fraction.toDouble(),
  ).translate(clipped);
}

ui.Rect _translatedScope(ui.Rect scope, _TileTranslation translation) {
  final xDimension = scope.width / translation.fraction;
  final yDimension = scope.height / translation.fraction;
  return ui.Rect.fromLTWH(
    xDimension * translation.xOffset,
    yDimension * translation.yOffset,
    xDimension,
    yDimension,
  );
}

class _TileTranslation {
  final int fraction;
  final int xOffset;
  final int yOffset;
  final int translatedZ;
  final int translatedX;
  final int translatedY;

  bool get isTranslated => fraction > 1;

  const _TileTranslation({
    required this.fraction,
    required this.xOffset,
    required this.yOffset,
    required this.translatedZ,
    required this.translatedX,
    required this.translatedY,
  });

  factory _TileTranslation.forZoom(int z, int x, int y, int maximumZoom) {
    if (z <= maximumZoom) {
      return _TileTranslation(
        fraction: 1,
        xOffset: 0,
        yOffset: 0,
        translatedZ: z,
        translatedX: x,
        translatedY: y,
      );
    }
    final divisor = 1 << (z - maximumZoom);
    return _TileTranslation(
      fraction: divisor,
      xOffset: x % divisor,
      yOffset: y % divisor,
      translatedZ: maximumZoom,
      translatedX: x ~/ divisor,
      translatedY: y ~/ divisor,
    );
  }
}

String _invalidStyle(String url) =>
    'Uri does not appear to be a valid style: $url';

class ExtendedStyleUriMapper {
  static const vkScheme = 'mmr';
  final String _key;

  ExtendedStyleUriMapper({required String key}) : _key = key;

  String map(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == vkScheme) {
      return _toVKUri(_authenticate(parsed));
    }
    return _replaceKey(uri);
  }

  String mapSource(String styleUri, String sourceUri) {
    final parsed = Uri.parse(sourceUri);
    if (parsed.scheme == vkScheme) {
      return _toVKUri(_authenticate(parsed, timestamp: true));
    }
    return _replaceKey(sourceUri);
  }

  List<SpriteUri> mapSprite(String styleUri, String spriteUri) {
    final parsed = Uri.parse(spriteUri);
    if (parsed.scheme == vkScheme) {
      final jsonUri = parsed.replace(path: '${parsed.path}.json');
      final imageUri = parsed.replace(path: '${parsed.path}.png');
      final json2x = parsed.replace(path: '${parsed.path}@2x.json');
      final image2x = parsed.replace(path: '${parsed.path}@2x.png');
      return [
        SpriteUri(
          json: _toVKUri(_authenticate(json2x, timestamp: true)),
          image: _toVKUri(_authenticate(image2x, timestamp: true)),
        ),
        SpriteUri(
          json: _toVKUri(_authenticate(jsonUri, timestamp: true)),
          image: _toVKUri(_authenticate(imageUri, timestamp: true)),
        ),
      ];
    }
    final parameters = Uri.parse(map(styleUri)).queryParameters;
    return [
      _toSpriteUri(spriteUri, parameters, '@2x'),
      _toSpriteUri(spriteUri, parameters, ''),
    ];
  }

  String mapTiles(String tileUri) {
    final parsed = Uri.parse(tileUri);
    if (parsed.scheme == vkScheme) {
      final mapped =
          tileUri.replaceFirst('$vkScheme://', 'https://tiles.maps.vk.com/');
      return _authenticateString(mapped);
    }
    return _replaceKey(tileUri);
  }

  SpriteUri _toSpriteUri(
    String spriteUri,
    Map<String, String> parameters,
    String suffix,
  ) {
    final query = parameters.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return SpriteUri(
      json: '$spriteUri$suffix.json?secure&$query',
      image: '$spriteUri$suffix.png?secure&$query',
    );
  }

  String _replaceKey(String url) =>
      url.replaceAll('{key}', Uri.encodeQueryComponent(_key));

  String _toVKUri(String source) =>
      source.replaceFirst('$vkScheme://', 'https://maps.vk.com/');

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

class SpriteUri {
  final String json;
  final String image;

  SpriteUri({required this.json, required this.image});
}
