import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_core/domain/place_info.dart';
import 'package:time_machine_cloud/services/cloud_base.dart';
import 'package:time_machine_cloud/services/image_cache.dart';
import 'package:time_machine_cloud/services/network_service.dart';
import 'package:time_machine_server/handler.dart';
import 'package:time_machine_server/rate_limit.dart';

class _FakeProvider implements DataProvider {
  @override
  Future<Picture> fetch(Picture original) async =>
      original.id == 'missing' ? throw StateError('missing') : original;

  @override
  Future<List<Picture>> findIn({
    required Area area,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [
    Picture(
      id: '1',
      url: 'https://fake.example/1.jpg',
      latitude: 1.0,
      longitude: 2.0,
      provider: 'fake',
    ),
  ];

  @override
  Future<List<Picture>> findNear({
    required Location location,
    required double radius,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [
    Picture(
      id: '2',
      url: 'https://fake.example/2.jpg',
      latitude: 3.0,
      longitude: 4.0,
      provider: 'fake',
    ),
  ];
}

class _FakeGeocoder implements GeocodingService {
  @override
  Future<List<PlaceInfo>> searchAddress(String query) async => [
    const PlaceInfo(name: 'Fake Place', lat: 1.0, lng: 2.0),
  ];

  @override
  Future<List<PlaceInfo>> searchCoordinates(Location location) async => [
    const PlaceInfo(name: 'Near Fake', lat: 3.0, lng: 4.0),
  ];
}

class _ImageAdapter implements dio.HttpClientAdapter {
  _ImageAdapter(this.data);

  final List<int> data;

  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => dio.ResponseBody(
    Stream.value(Uint8List.fromList(data)),
    200,
    headers: {
      'content-type': ['image/jpeg'],
    },
  );

  @override
  void close({bool force = false}) {}
}

NetworkService _network() => NetworkService(
  clouds: const <String, CloudBase>{},
  geocoders: {'fake': _FakeGeocoder()},
  providers: {'pastvu': _FakeProvider()},
);

Handler _handler({
  CachedImageFetcher? imageFetcher,
  RateLimiter? rateLimiter,
  Directory? webBuildDir,
}) => createHandler(
  networkService: _network(),
  imageFetcher: imageFetcher,
  rateLimiter: rateLimiter,
  webBuildDir: webBuildDir,
);

Request _post(String path, Object body) => Request(
  'POST',
  Uri.parse('http://localhost$path'),
  body: json.encode(body),
  headers: const {'content-type': 'application/json'},
);

Future<Map<String, dynamic>> _readJson(Response response) async =>
    json.decode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  test('GET /health returns ok', () async {
    final response = await _handler()(Request('GET', Uri.parse('http://localhost/health')));
    expect(response.statusCode, 200);
    expect(await _readJson(response), {'status': 'ok'});
  });

  test('POST /api/findIn proxies and serializes pictures', () async {
    final response = await _handler()(_post('/api/findIn', {
      'area': {
        'minLat': 1.0,
        'minLng': 2.0,
        'maxLat': 3.0,
        'maxLng': 4.0,
      },
      'startDate': '1900-01-01T00:00:00.000',
      'endDate': '1920-01-01T00:00:00.000',
    }));
    expect(response.statusCode, 200);
    final body = await _readJson(response);
    expect(body.containsKey('pastvu'), isTrue);
    final pictures = body['pastvu'] as List;
    expect(pictures, hasLength(1));
    final picture = Picture.fromJson(pictures.first as Map<String, dynamic>);
    expect(picture.id, '1');
    expect(picture.provider, 'pastvu');
  });

  test('POST /api/findNear proxies', () async {
    final response = await _handler()(_post('/api/findNear', {
      'location': {'lat': 1.0, 'lng': 2.0},
      'radius': 5000,
    }));
    expect(response.statusCode, 200);
    final body = await _readJson(response);
    expect(body.containsKey('pastvu'), isTrue);
  });

  test('POST /api/fetchPicture returns picture json', () async {
    final response = await _handler()(_post('/api/fetchPicture', {
      'picture': {
        'id': '1',
        'url': 'https://fake.example/1.jpg',
        'latitude': 1.0,
        'longitude': 2.0,
        'provider': 'pastvu',
      },
    }));
    expect(response.statusCode, 200);
    final body = await _readJson(response);
    expect(body['picture'], isNotNull);
  });

  test('POST /api/fetchPicture returns 404 for unknown provider', () async {
    final response = await _handler()(_post('/api/fetchPicture', {
      'picture': {
        'id': '1',
        'url': 'https://fake.example/1.jpg',
        'latitude': 1.0,
        'longitude': 2.0,
        'provider': 'unknown',
      },
    }));
    expect(response.statusCode, 404);
  });

  test('POST /api/searchAddress returns places', () async {
    final response = await _handler()(_post('/api/searchAddress', {
      'query': 'Fake Place',
    }));
    expect(response.statusCode, 200);
    final body = json.decode(await response.readAsString()) as List;
    expect(body, hasLength(1));
    expect(PlaceInfo.fromJson(body.first as Map<String, dynamic>).name, 'Fake Place');
  });

  test('POST /api/searchCoordinates returns places', () async {
    final response = await _handler()(_post('/api/searchCoordinates', {
      'location': {'lat': 1.0, 'lng': 2.0},
    }));
    expect(response.statusCode, 200);
    final body = json.decode(await response.readAsString()) as List;
    expect(body, hasLength(1));
    expect(PlaceInfo.fromJson(body.first as Map<String, dynamic>).lat, 3.0);
  });

  test('GET /api/image returns proxied bytes with content type', () async {
    final dioImpl = dio.Dio()..httpClientAdapter = _ImageAdapter(utf8.encode('fakepng'));
    final fetcher = CachedImageFetcher(dio: dioImpl);
    final response = await _handler(imageFetcher: fetcher)(Request(
      'GET',
      Uri.parse('http://localhost/api/image?url=https%3A%2F%2Fpastvu.com%2Fimg.jpg'),
    ));
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'image/jpeg');
    expect(await response.readAsString(), 'fakepng');
  });

  test('GET /api/image returns etag and honors If-None-Match with 304', () async {
    final dioImpl = dio.Dio()..httpClientAdapter = _ImageAdapter(utf8.encode('fakepng'));
    final fetcher = CachedImageFetcher(dio: dioImpl);
    final handler = _handler(imageFetcher: fetcher);
    final uri = Uri.parse('http://localhost/api/image?url=https%3A%2F%2Fpastvu.com%2Fimg.jpg');
    final first = await handler(Request('GET', uri));
    expect(first.statusCode, 200);
    final etag = first.headers['etag'];
    expect(etag, isNotEmpty);
    final revalidated = await handler(Request('GET', uri, headers: {'if-none-match': etag!}));
    expect(revalidated.statusCode, 304);
    expect(revalidated.headers['etag'], etag);
    expect(await revalidated.readAsString(), isEmpty);
  });

  test('GET /api/image rejects hosts outside the allow-list', () async {
    final dioImpl = dio.Dio()..httpClientAdapter = _ImageAdapter(utf8.encode('x'));
    final fetcher = CachedImageFetcher(dio: dioImpl, allowedHosts: const ['pastvu.com']);
    final response = await _handler(imageFetcher: fetcher)(Request(
      'GET',
      Uri.parse('http://localhost/api/image?url=https%3A%2F%2Fevil.example%2Fimg.jpg'),
    ));
    expect(response.statusCode, 403);
  });

  test('OPTIONS preflight is answered with CORS headers', () async {
    final response = await _handler()(Request('OPTIONS', Uri.parse('http://localhost/api/findIn')));
    expect(response.statusCode, 200);
    expect(response.headers['Access-Control-Allow-Origin'], '*');
    expect(response.headers['Access-Control-Allow-Headers'], contains('authorization'));
  });

  test('rate limit returns 429 once exceeded', () async {
    final limiter = RateLimiter(maxRequestsPerWindow: 2);
    final handler = _handler(rateLimiter: limiter);
    final first = await handler(_post('/api/findIn', {'area': _area()}));
    final second = await handler(_post('/api/findIn', {'area': _area()}));
    final third = await handler(_post('/api/findIn', {'area': _area()}));
    expect(first.statusCode, 200);
    expect(second.statusCode, 200);
    expect(third.statusCode, 429);
  });

  test('malformed json returns 400', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/api/findIn'),
      body: 'not json',
      headers: const {'content-type': 'application/json'},
    );
    final response = await _handler()(request);
    expect(response.statusCode, 400);
  });

  group('web static serving', () {
    late Directory webDir;
    late Handler handler;

    setUp(() {
      webDir = Directory.systemTemp.createTempSync('tm_web_');
      File('${webDir.path}/index.html').writeAsStringSync('<html>app</html>');
      File('${webDir.path}/auth.html')
          .writeAsStringSync('<html>callback</html>');
      Directory('${webDir.path}/assets').createSync();
      File('${webDir.path}/assets/main.dart.js').writeAsStringSync('console.log(1);');
      handler = _handler(webBuildDir: webDir);
    });

    tearDown(() {
      webDir.deleteSync(recursive: true);
    });

    test('GET / serves index.html', () async {
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('text/html'));
      expect(await response.readAsString(), '<html>app</html>');
    });

    test('deep-link route falls back to index.html', () async {
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/photos/123')),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), '<html>app</html>');
    });

    test('static assets are served from disk', () async {
      final response = await handler(Request(
        'GET',
        Uri.parse('http://localhost/assets/main.dart.js'),
      ));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('javascript'));
      expect(await response.readAsString(), 'console.log(1);');
    });

    test('missing asset returns 404, not index.html', () async {
      final response = await handler(Request(
        'GET',
        Uri.parse('http://localhost/assets/missing.js'),
      ));
      expect(response.statusCode, 404);
    });

    test('POST to non-has api path is rejected', () async {
      final response = await handler(Request(
        'POST',
        Uri.parse('http://localhost/'),
        body: 'x',
      ));
      expect(response.statusCode, 405);
    });

    test('API routes still work when web serving is enabled', () async {
      final response = await handler(_post('/api/findIn', {'area': _area()}));
      expect(response.statusCode, 200);
    });

    test('auth routes reach the API when web serving is enabled', () async {
      final response = await handler(Request(
        'GET',
        Uri.parse(
          'http://localhost/auth/yandex/start'
          '?redirect_uri=http%3A%2F%2Flocalhost%2Fauth.html',
        ),
      ));
      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['authUrl'], contains('oauth.yandex.ru'));
      final authUrl = Uri.parse(body['authUrl'] as String);
      expect(
        authUrl.queryParameters['redirect_uri'],
        'http://localhost/auth/yandex/callback',
      );
    });

    test('auth callback page is served as a static file', () async {
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/auth.html')),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), '<html>callback</html>');
    });

    test('provider callback routes bypass static web serving', () async {
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/oauth2redirect-dropbox')),
      );
      expect(response.statusCode, 400);
    });
  });

  group('OAuth start validation', () {
    test('rejects a non-http redirect_uri', () async {
      final response = await _handler()(Request(
        'GET',
        Uri.parse(
          'http://localhost/auth/yandex/start'
          '?redirect_uri=com.fakegem.historylens%3A%2Foauth2redirect',
        ),
      ));
      expect(response.statusCode, 400);
    });

    test('refresh requires a refresh token', () async {
      final response = await _handler()(Request(
        'POST',
        Uri.parse('http://localhost/auth/yandex/refresh'),
        body: json.encode(const <String, String>{}),
        headers: const {'content-type': 'application/json'},
      ));
      expect(response.statusCode, 400);
    });

    test('start forwards the client_id supplied by the web build', () async {
      final response = await _handler()(Request(
        'GET',
        Uri.parse(
          'http://localhost/auth/yandex/start'
          '?redirect_uri=http%3A%2F%2Flocalhost%2Fauth.html'
          '&client_id=web-client-id',
        ),
      ));
      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['authUrl'], contains('client_id=web-client-id'));
    });

    test('dropbox start uses the registered callback path', () async {
      final response = await _handler()(Request(
        'GET',
        Uri.parse(
          'http://localhost/auth/dropbox/start'
          '?redirect_uri=http%3A%2F%2Flocalhost%2Fauth.html',
        ),
      ));
      expect(response.statusCode, 200);
      final body = await _readJson(response);
      final authUrl = Uri.parse(body['authUrl'] as String);
      expect(
        authUrl.queryParameters['redirect_uri'],
        'http://localhost/oauth2redirect-dropbox',
      );
    });

    test('dropbox callback route accepts the provider redirect', () async {
      final handler = _handler();
      final start = await handler(Request(
        'GET',
        Uri.parse(
          'http://localhost/auth/dropbox/start'
          '?redirect_uri=http%3A%2F%2Flocalhost%2Fauth.html',
        ),
      ));
      final authUrl = Uri.parse(
        (await _readJson(start))['authUrl'] as String,
      );
      final state = authUrl.queryParameters['state']!;
      final callback = await handler(Request(
        'GET',
        Uri.parse(
          'http://localhost/oauth2redirect-dropbox'
          '?state=$state&error=access_denied&error_description=user+cancelled',
        ),
      ));
      expect(callback.statusCode, 302);
      final location = Uri.parse(callback.headers['location']!);
      expect(location.path, '/auth.html');
      expect(location.queryParameters['provider'], 'dropbox');
      expect(location.queryParameters['error'], 'access_denied');
    });
  });
}

Map<String, dynamic> _area() => {
  'minLat': 1.0,
  'minLng': 2.0,
  'maxLat': 3.0,
  'maxLng': 4.0,
};