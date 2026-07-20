import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles/src/style/uri_mapper.dart';
import 'package:vector_map_tiles/src/provider/network_vector_tile_provider.dart';
import 'package:vector_map_tiles/src/tile_providers.dart';
import 'package:vector_map_tiles/src/vector_tile_provider.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

class VectorService {
  final Dio dio;
  final String vkApiKey;
  final _styleCache = <String, Style>{};

  void clearStyleCache() => _styleCache.clear();

  VectorService({
    this.vkApiKey = '6960065e78ec62fc5f7ae70b0472ffcb37ad03630e3073560b9c8dba3e3dff83',
    String? userAgent,
  }) : dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      if (userAgent != null)
        'User-Agent': userAgent,
      'Referer': 'https://tiles.maps.vk.com/',
      'Origin': 'https://tiles.maps.vk.com',
      'Priority': 'u=4',
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

  Future<Style> loadStyle(String uri) async {
    final cached = _styleCache[uri];
    if (cached != null) return cached;
    final uriMapper = ExtendedStyleUriMapper(key: vkApiKey);
    final url = uriMapper.map(uri);
    final response = await dio.get(url);
    final style = response.data;
    if (style is! Map<String, dynamic>) {
      throw _invalidStyle(url);
    }
    final sources = style['sources'];
    if (sources is! Map) {
      throw _invalidStyle(url);
    }
    final providerByName = await _readProviderByName(sources, uri);
    final name = style['name'] as String?;

    final center = style['center'];
    LatLng? centerPoint;
    if (center is List && center.length == 2) {
      centerPoint =
          LatLng((center[1] as num).toDouble(), (center[0] as num).toDouble());
    }
    double? zoom = (style['zoom'] as num?)?.toDouble();
    if (zoom != null && zoom < 2) {
      zoom = null;
      centerPoint = null;
    }
    final spriteUri = style['sprite'];
    SpriteStyle? sprites;
    if (spriteUri is String && spriteUri.trim().isNotEmpty) {
      final spriteUris = uriMapper.mapSprite(uri, spriteUri);
      for (final spriteUri in spriteUris) {
        dynamic spritesJson;
        try {
          final spritesResponse = await dio.get(spriteUri.json);
          spritesJson = spritesResponse.data;
        } catch (e) {
          debugPrint('error reading sprite uri: ${spriteUri.json}');
          continue;
        }

        sprites = SpriteStyle(
          atlasProvider: () async {
            final imageResponse = await dio.get(
              spriteUri.image,
              options: Options(responseType: ResponseType.bytes),
            );
            return imageResponse.data;
          },
          index: SpriteIndexReader(logger: Logger.console()).read(spritesJson),
        );
        break;
      }
    }
    final result = Style(
      theme: ThemeReader(logger: Logger.console()).read(style),
      providers: TileProviders(providerByName),
      sprites: sprites,
      name: name,
      center: centerPoint,
      zoom: zoom,
    );
    _styleCache[uri] = result;
    return result;
  }

  Future<Map<String, VectorTileProvider>> _readProviderByName(Map sources, String uri) async {
    final providers = <String, VectorTileProvider>{};
    final sourceEntries = sources.entries.toList();
    for (final entry in sourceEntries) {
      final sourceType = entry.value['type'];
      var type = TileProviderType.values
          .where((e) => e.name.replaceAll('_', '-') == sourceType)
          .firstOrNull;
      if (type == null) continue;
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
        providers[entry.key] = NetworkVectorTileProvider(
          type: type,
          urlTemplate: tileUrl,
          httpHeaders: {
            'Referer': 'https://tiles.maps.vk.com/',
            'Origin': 'https://tiles.maps.vk.com',
          },
          maximumZoom: maxzoom,
          minimumZoom: minzoom,
        );
      }
    }
    if (providers.isEmpty) {
      throw 'Unexpected response';
    }
    return providers;
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