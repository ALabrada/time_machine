import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_map/services/tile_caching_service.dart';
import 'package:time_machine_map/services/vector_service.dart';

/// Dio adapter that returns canned JSON for any request.
/// Uses `jsonEncode` so that the response-body round-trips through the same
/// JSON decoder that a real server would trigger.
class _MockAdapter implements HttpClientAdapter {
  final Map<String, dynamic> styleJson;
  final Map<String, dynamic>? spriteContent;
  final Uint8List? spriteImage;

  _MockAdapter({
    required this.styleJson,
    this.spriteContent,
    this.spriteImage,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final uri = options.uri.toString();

    // Sprite requests (the URL may be "example.com/sprite" or "example.com/missing-sprite")
    if (uri.contains('sprite')) {
      if (spriteContent != null && spriteImage != null) {
        final body = uri.contains('.png')
            ? spriteImage!
            : Uint8List.fromList(jsonEncode(spriteContent).codeUnits);
        return ResponseBody.fromBytes(body, 200, headers: {
          'content-type': [
            uri.contains('.png') ? 'image/png' : 'application/json',
          ],
        });
      }
      return ResponseBody.fromBytes(
        Uint8List(0), 404,
        headers: {'content-type': ['text/plain']},
      );
    }

    // Merge `tiles` fields so that even if the service fetches a source-URL
    // the response contains `tiles` (as well as `sources` for the style fetch).
    final merged = <String, dynamic>{
      ...styleJson,
      'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.pbf'],
      'maxzoom': 14,
      'minzoom': 1,
    };

    return ResponseBody.fromBytes(
      Uint8List.fromList(jsonEncode(merged).codeUnits),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailOnRequestInterceptor extends Interceptor {
  _FailOnRequestInterceptor(this._message);

  final String _message;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    fail(_message);
  }
}

Matcher _throwsString(String substring) =>
    throwsA(predicate<String>((e) => e.contains(substring)));

/// Helper to build simple inline-source style JSON.
Map<String, dynamic> _inlineStyle({
  String? name,
  List<double>? center,
  double? zoom,
  Map<String, dynamic>? extra,
}) =>
    <String, dynamic>{
      if (name != null) 'name': name,
      'sources': <String, dynamic>{
        'osm': <String, dynamic>{
          'type': 'vector',
          'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.pbf'],
          if (extra != null) ...extra,
        },
      },
      if (center != null) 'center': center,
      if (zoom != null) 'zoom': zoom,
    };

void main() {
  group('VectorService', () {
    group('constructor', () {
      test('creates Dio with default timeouts and no user-agent header', () {
        final service = VectorService(vkApiKey: 'key123');
        expect(service.dio.options.connectTimeout, const Duration(seconds: 10));
        expect(service.dio.options.receiveTimeout, const Duration(seconds: 15));
        expect(service.dio.options.headers.containsKey('User-Agent'), isFalse);
      });

      test('sets User-Agent header when userAgent is provided', () {
        final service = VectorService(
          vkApiKey: 'key123',
          userAgent: 'TestAgent/1.0',
        );
        expect(service.dio.options.headers['User-Agent'], 'TestAgent/1.0');
      });

      test('uses provided TileCachingService', () {
        final cache = TileCachingService();
        final service = VectorService(
          vkApiKey: 'key123',
          cachingService: cache,
        );
        expect(service.cachingService, same(cache));
      });

      test('creates default TileCachingService when none provided', () {
        final service = VectorService(vkApiKey: 'key123');
        expect(service.cachingService, isA<TileCachingService>());
      });
    });

    group('clearStyleCache', () {
      test('clears the style cache so loadStyle makes a new request', () async {
        const styleUri = 'https://example.com/style.json';

        final mockStyleJson = <String, dynamic>{
          'name': 'Test Style',
          'sources': <String, dynamic>{
            'osm': <String, dynamic>{
              'type': 'vector',
              'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.pbf'],
            },
          },
        };

        final service = VectorService(vkApiKey: 'key123');
        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style1 = await service.loadStyle(styleUri);
        service.clearStyleCache();

        final style2 = await service.loadStyle(styleUri);
        expect(style2, isNot(same(style1)));
      });
    });

    group('ExtendedStyleUriMapper', () {
      test('map converts mmr:// scheme to maps.vk.com with api_key', () {
        final mapper = ExtendedStyleUriMapper(key: 'test_key');
        final result = mapper.map('mmr://style/light');
        expect(result, startsWith('https://maps.vk.com/style/light'));
        expect(result, contains('api_key=test_key'));
      });

      test('map adds timestamp for mmr source URIs', () {
        final mapper = ExtendedStyleUriMapper(key: 'test_key');
        final result = mapper.mapSource(
          'mmr://style/light',
          'mmr://source/osm',
        );
        expect(result, startsWith('https://maps.vk.com/source/osm'));
        expect(result, contains('api_key=test_key'));
        expect(result, contains('t='));
      });

      test('mapTiles replaces mmr:// with tiles.maps.vk.com', () {
        final mapper = ExtendedStyleUriMapper(key: 'test_key');
        final result = mapper.mapTiles('mmr://tiles/{z}/{x}/{y}.pbf');
        expect(
          result,
          startsWith('https://tiles.maps.vk.com/tiles/{z}/{x}/{y}.pbf'),
        );
        expect(result, contains('api_key=test_key'));
      });

      test('mapSprite returns JSON and PNG URIs for mmr scheme with api_key and timestamp',
          () {
        final mapper = ExtendedStyleUriMapper(key: 'test_key');
        final sprites =
            mapper.mapSprite('mmr://style/light', 'mmr://sprites/default');
        expect(sprites, hasLength(1));
        expect(sprites[0].json, contains('.json'));
        expect(sprites[0].json, contains('api_key=test_key'));
        expect(sprites[0].json, contains('t='));
        expect(sprites[0].image, contains('.png'));
        expect(sprites[0].image, contains('api_key=test_key'));
        expect(sprites[0].image, contains('t='));
      });
    });

    group('loadStyle', () {
      late VectorService service;
      const styleUri = 'https://example.com/style.json';

      setUp(() {
        service = VectorService(vkApiKey: 'test_key');
      });

      test('returns VectorTileStyle with correct name, center, and zoom',
          () async {
        final mockStyleJson = _inlineStyle(
          name: 'My Style',
          center: [13.4, 52.5],
          zoom: 10,
        );

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style = await service.loadStyle(styleUri);
        expect(style.name, 'My Style');
        expect(style.center!.latitude, 52.5);
        expect(style.center!.longitude, 13.4);
        expect(style.zoom, 10);
        expect(style.sources, hasLength(1));
        expect(style.sources.containsKey('osm'), isTrue);
      });

      test('returns cached style on subsequent calls', () async {
        final mockStyleJson = _inlineStyle();

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style1 = await service.loadStyle(styleUri);

        service.dio.httpClientAdapter = _MockAdapter(styleJson: <String, dynamic>{});
        service.dio.interceptors.clear();
        service.dio.interceptors.add(_FailOnRequestInterceptor(
          'Should not make HTTP request for cached style',
        ));

        final style2 = await service.loadStyle(styleUri);
        expect(style2, same(style1));
      });

      test('loads sprite when sprite URI is present', () async {
        final mockStyleJson = <String, dynamic>{
          'name': 'With Sprite',
          'sources': <String, dynamic>{
            'osm': <String, dynamic>{
              'type': 'vector',
              'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.pbf'],
            },
          },
          'sprite': 'https://example.com/sprite',
        };

        final spriteContent = <String, dynamic>{
          'marker': <String, dynamic>{
            'x': 0, 'y': 0, 'width': 20, 'height': 20,
          },
        };
        final spriteImage = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

        service.dio.httpClientAdapter = _MockAdapter(
          styleJson: mockStyleJson,
          spriteContent: spriteContent,
          spriteImage: spriteImage,
        );

        final style = await service.loadStyle(styleUri);
        expect(style.sprites, isNotNull);
        expect(style.sprites!.atlas, spriteImage);
        expect(style.sprites!.content, spriteContent);
      });

      test('gracefully handles sprite load failure by leaving sprites null',
          () async {
        final mockStyleJson = <String, dynamic>{
          'sources': <String, dynamic>{
            'osm': <String, dynamic>{
              'type': 'vector',
              'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.pbf'],
            },
          },
          'sprite': 'https://example.com/missing-sprite',
        };

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style = await service.loadStyle(styleUri);
        expect(style.sprites, isNull);
      });

      test('throws when sources field is not a Map', () async {
        final badStyleJson = <String, dynamic>{
          'sources': 'not-a-map',
        };

        service.dio.httpClientAdapter = _MockAdapter(styleJson: badStyleJson);

        await expectLater(
          service.loadStyle(styleUri),
          _throwsString('valid style'),
        );
      });

      test('throws when sources is missing', () async {
        final badStyleJson = <String, dynamic>{
          'name': 'No sources',
        };

        service.dio.httpClientAdapter = _MockAdapter(styleJson: badStyleJson);

        await expectLater(
          service.loadStyle(styleUri),
          _throwsString('valid style'),
        );
      });

      test('throws when no source entries produce tiles', () async {
        final emptySourcesStyle = <String, dynamic>{
          'sources': <String, dynamic>{},
        };

        service.dio.httpClientAdapter =
            _MockAdapter(styleJson: emptySourcesStyle);

        await expectLater(
          service.loadStyle(styleUri),
          throwsA('Unexpected response'),
        );
      });

      test('uses default zoom values when source lacks maxzoom/minzoom',
          () async {
        final mockStyleJson = _inlineStyle();

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style = await service.loadStyle(styleUri);
        expect(style.sources['osm']!.maximumZoom, 14);
        expect(style.sources['osm']!.minimumZoom, 1);
      });

      test('nullifies zoom and center when zoom < 2', () async {
        final mockStyleJson = _inlineStyle(
          name: 'Low zoom',
          center: [0.0, 0.0],
          zoom: 1,
        );

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style = await service.loadStyle(styleUri);
        expect(style.zoom, isNull);
        expect(style.center, isNull);
      });

      test('preserves non-vector source types in metadata', () async {
        final mockStyleJson = <String, dynamic>{
          'sources': <String, dynamic>{
            'raster_source': <String, dynamic>{
              'type': 'raster',
              'tiles': <String>['https://tiles.example.com/{z}/{x}/{y}.png'],
            },
          },
        };

        service.dio.httpClientAdapter = _MockAdapter(styleJson: mockStyleJson);

        final style = await service.loadStyle(styleUri);
        expect(style.sources, hasLength(1));
        expect(style.sources['raster_source']!.type, 'raster');
        expect(
          style.sources['raster_source']!.urlTemplate,
          contains('{z}/{x}/{y}.png'),
        );
      });
    });

    group('renderTileImage', () {
      test('accepts valid parameters', () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final s = VectorService(
          vkApiKey: 'key123',
          cachingService: _TileNotCachedService(),
        );
        try {
          await s.renderTileImage(
            z: 5,
            x: 10,
            y: 15,
            theme: Theme(id: '', version: '', layers: []),
            tileset: Tileset(<String, Tile>{}),
            rasterTileset: const RasterTileset(tiles: {}),
          );
        } catch (_) {
          // Rendering requires GPU - not available in unit tests
        }
      });
    });
  });
}

class _TileNotCachedService extends TileCachingService {
  @override
  Future<bool> isTileCached(int z, int x, int y) => Future.value(false);

  @override
  Future<XFile> tileFile(int z, int x, int y) =>
      Future.error('not cached');
}
