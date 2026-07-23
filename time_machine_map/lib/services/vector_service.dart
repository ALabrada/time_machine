import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles/src/style/uri_mapper.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

import '../domain/vector_tile_style.dart';

class VectorService {
  final Dio dio;
  final String vkApiKey;
  final _styleCache = <String, VectorTileStyle>{};

  Directory? _tileCacheDir;

  VectorService({
    required this.vkApiKey,
    String? userAgent,
  }) : dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      if (userAgent != null)
        'User-Agent': userAgent,
    },
  )) {
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

  Future<Directory> _tileCacheDirectory() async {
    if (_tileCacheDir != null) return _tileCacheDir!;
    final cacheDir = await getApplicationCacheDirectory();
    final dirPath = p.join(cacheDir.path, 'vector_tiles');
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _tileCacheDir = dir;
    return dir;
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
      .where((e) => e is MapEntry<String, VectorTileSource>)
      .toList();
    if (sourceEntries.isEmpty) {
      throw 'Unexpected response';
    }
    return Map.fromIterable(sourceEntries);
  }

  Future<File> _tileFile(Directory cacheDir, int z, int x, int y) async {
    final dir = Directory('${cacheDir.path}/$z/$x');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/$y.png');
  }

  Future<File> renderTile({
    required int z,
    required int x,
    required int y,
    required double zoom,
    required VectorTileStyle style,
    TileRenderCanceller? canceller,
  }) async {
    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    final cacheDir = await _tileCacheDirectory();
    final file =  await _tileFile(cacheDir, z, x, y);
    if (await file.exists() && await file.length() > 0) return file;

    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    await Isolate.run(() => _downloadAndRenderInIsolate(
      z: z,
      x: x,
      y: y,
      zoom: zoom,
      style: style,
      fileName: file.path,
    ));
    return file;
  }
}

/// Allows cancelling an in-progress [VectorService.renderTile] call.
class TileRenderCanceller {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

Future<void> _downloadAndRenderInIsolate({
  required int z,
  required int x,
  required int y,
  required double zoom,
  required VectorTileStyle style,
  required String fileName,
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
      debugPrint('Error processing source $sourceName in isolate: $e');
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

  final data = await image.toPng();
  await File(fileName).writeAsBytes(data);
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