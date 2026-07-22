import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles/src/style/uri_mapper.dart';
import 'package:vector_tile_renderer/src/model/geometry_model.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

class VectorService {
  final Dio dio;
  final String vkApiKey;
  final _styleCache = <String, Style>{};
  final _rawStyleCache = <String, Map<String, dynamic>>{};

  void clearStyleCache() {
    _styleCache.clear();
    _rawStyleCache.clear();
  }

  Future<Map<String, dynamic>> loadRawStyle(String uri) async {
    final cached = _rawStyleCache[uri];
    if (cached != null) return cached;
    await loadStyle(uri);
    return _rawStyleCache[uri]!;
  }

  Future<StyleWithRaw> loadStyleWithRaw(String uri) async {
    final style = await loadStyle(uri);
    return StyleWithRaw(style: style, raw: _rawStyleCache[uri]!);
  }

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

  Future<Style> loadStyle(String uri) async {
    final cached = _styleCache[uri];
    if (cached != null) return cached;
    final uriMapper = ExtendedStyleUriMapper(key: vkApiKey);
    final url = uriMapper.map(uri);
    final response = await dio.get(url);
    final styleJson = response.data as Map<String, dynamic>;
    _rawStyleCache[uri] = styleJson;
    final sources = styleJson['sources'];
    if (sources is! Map) {
      throw _invalidStyle(url);
    }
    final providerByName = await _readProviderByName(sources, uri);
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
      theme: ThemeReader(logger: Logger.console()).read(styleJson),
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

  Directory? _tileCacheDir;

  Future<Directory> _tileCacheDirectory() async {
    if (_tileCacheDir != null) return _tileCacheDir!;
    final dir = Directory(
        '${(await Directory.systemTemp).path}/time_machine_tiles');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _tileCacheDir = dir;
    return dir;
  }

  File _tileFile(Directory cacheDir, int z, int x, int y) {
    final dir = Directory('${cacheDir.path}/$z/$x');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$y.png');
  }

  Future<File> renderTile({
    required int z,
    required int x,
    required int y,
    required double zoom,
    required List<String> sources,
    required List<Uint8List> pbfs,
    required Map<String, dynamic> styleJson,
    TileRenderCanceller? canceller,
  }) async {
    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    final cacheDir = await _tileCacheDirectory();
    final file = _tileFile(cacheDir, z, x, y);
    if (await file.exists() && await file.length() > 0) return file;

    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    final p = ReceivePort();
    final isolateData = _IsolateData(
      pbfs: pbfs.map((b) => TransferableTypedData.fromList([b])).toList(),
      styleJson: styleJson,
      sources: sources,
      zoom: zoom,
      sendPort: p.sendPort,
    );
    final isolate = await Isolate.spawn(_isolateMain, isolateData);
    canceller?.attachIsolate(isolate);
    final serialized = await p.first as Map<String, dynamic>;

    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    final tilesData = serialized['tiles'] as Map<String, dynamic>;
    if (tilesData.isEmpty) throw 'No tiles rendered';

    final theme = ThemeReader(logger: Logger.console()).read(styleJson);
    final logger = Logger.console();

    final tilesBySource = <String, Tile>{};
    for (final entry in tilesData.entries) {
      final tileData = _decodeTileData(entry.value as Map<String, dynamic>);
      tilesBySource[entry.key] = tileData.toTile();
    }

    if (canceller?.isCancelled == true) throw 'Tile render cancelled';

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    Renderer(theme: theme, logger: logger).render(
      canvas,
      TileSource(tileset: Tileset(tilesBySource)),
      zoomScaleFactor: 1.0,
      zoom: zoom,
      rotation: 0.0,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    return file;
  }
}

/// Allows cancelling an in-progress [VectorService.renderTile] call.
class TileRenderCanceller {
  Isolate? _isolate;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void attachIsolate(Isolate isolate) {
    if (_cancelled) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = isolate;
  }
}

// --- TileData serialization for isolate transfer ---

List _encodeFeature(TileDataFeature f) {
  final typeIdx = f.type.index;
  final props = f.properties;

  if (f.hasPoints) {
    return [typeIdx, props, f.points.map((p) => [p.x, p.y]).toList()];
  }
  if (f.hasLines) {
    return [
      typeIdx,
      props,
      f.lines
          .map((l) => l.points.map((p) => [p.x, p.y]).toList())
          .toList(),
    ];
  }
  if (f.hasPolygons) {
    return [
      typeIdx,
      props,
      f.polygons
          .map((pg) => pg.rings
              .map((r) => r.points.map((p) => [p.x, p.y]).toList())
              .toList())
          .toList(),
    ];
  }
  return [typeIdx, props, []];
}

TileDataFeature _decodeFeature(List data) {
  final type = TileFeatureType.values[data[0] as int];
  final props = data[1] as Map<String, dynamic>;
  final geom = data[2] as List;

  math.Point<double> pt(dynamic p) =>
      math.Point<double>(p[0] as double, p[1] as double);

  switch (type) {
    case TileFeatureType.point: {
      final pts = <math.Point<double>>[];
      for (final p in geom) {
        pts.add(pt(p));
      }
      return TileDataFeature(
        type: type, properties: props, geometry: null, points: pts,
      );
    }
    case TileFeatureType.linestring: {
      final lines = <TileLine>[];
      for (final l in geom) {
        final pts = <math.Point<double>>[];
        for (final p in l as List) {
          pts.add(pt(p));
        }
        lines.add(TileLine(pts));
      }
      return TileDataFeature(
        type: type, properties: props, geometry: null, lines: lines,
      );
    }
    case TileFeatureType.polygon: {
      final polys = <TilePolygon>[];
      for (final pg in geom) {
        final rings = <TileLine>[];
        for (final r in pg as List) {
          final pts = <math.Point<double>>[];
          for (final p in r as List) {
            pts.add(pt(p));
          }
          rings.add(TileLine(pts));
        }
        polys.add(TilePolygon(rings));
      }
      return TileDataFeature(
        type: type, properties: props, geometry: null, polygons: polys,
      );
    }
    case TileFeatureType.background:
    case TileFeatureType.none:
      return TileDataFeature(type: type, properties: props, geometry: null);
  }
}

Map<String, dynamic> _encodeLayer(TileDataLayer layer) => {
      'name': layer.name,
      'extent': layer.extent,
      'features': layer.features.map(_encodeFeature).toList(),
    };

TileDataLayer _decodeLayer(Map<String, dynamic> data) => TileDataLayer(
      name: data['name'] as String,
      extent: data['extent'] as int,
      features:
          (data['features'] as List).map((f) => _decodeFeature(f as List)).toList(),
    );

Map<String, dynamic> _encodeTileData(TileData data) =>
    {'layers': data.layers.map(_encodeLayer).toList()};

TileData _decodeTileData(Map<String, dynamic> data) => TileData(
      layers: (data['layers'] as List)
          .map((l) => _decodeLayer(l as Map<String, dynamic>))
          .toList(),
    );

class _IsolateData {
  final List<TransferableTypedData> pbfs;
  final Map<String, dynamic> styleJson;
  final List<String> sources;
  final double zoom;
  final SendPort sendPort;

  _IsolateData({
    required this.pbfs,
    required this.styleJson,
    required this.sources,
    required this.zoom,
    required this.sendPort,
  });
}

void _isolateMain(_IsolateData data) {
  final theme = ThemeReader(logger: Logger.console()).read(data.styleJson);
  final logger = Logger.console();

  final tilesResult = <String, Map<String, dynamic>>{};
  for (int i = 0; i < data.sources.length; i++) {
    try {
      final pbf = data.pbfs[i].materialize().asUint8List();
      final vectorTile = VectorTileReader().read(pbf);
      final tileData = TileFactory(theme, logger).createTileData(vectorTile);
      tilesResult[data.sources[i]] = _encodeTileData(tileData);
    } catch (e) {
      debugPrint('Error processing source ${data.sources[i]}: $e');
    }
  }

  data.sendPort.send({'tiles': tilesResult});
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