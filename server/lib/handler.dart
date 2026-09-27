import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_cloud/services/image_cache.dart';
import 'package:time_machine_cloud/services/network_service.dart';

import 'network.dart';
import 'rate_limit.dart';

/// Builds the proxy handler.
///
/// Injectable for tests: pass a [NetworkService] built with fake
/// providers/geocoders and a [CachedImageFetcher] backed by a mock Dio.
///
/// When [webBuildDir] is set, requests that are not under `/api` or
/// `/health` are served as static files from that directory (the built
/// Flutter web app), with SPA fallback to `index.html`.
Handler createHandler({
  required NetworkService networkService,
  CachedImageFetcher? imageFetcher,
  RateLimiter? rateLimiter,
  Directory? webBuildDir,
  int maxBodyBytes = 1 << 20,
}) {
  final cached = imageFetcher ?? CachedImageFetcher();
  final limiter = rateLimiter ?? RateLimiter();

  final router = Router()
    ..get('/health', (Request request) => _ok({'status': 'ok'}))
    ..post('/api/findIn', (Request request) => _findIn(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ))
    ..post('/api/findNear', (Request request) => _findNear(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ))
    ..post('/api/fetchPicture', (Request request) => _fetchPicture(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ))
    ..post('/api/searchAddress', (Request request) => _searchAddress(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ))
    ..post('/api/searchCoordinates', (Request request) => _searchCoordinates(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ))
    ..get('/api/image', (Request request) => _image(
      request,
      networkService,
      cached,
      maxBodyBytes,
    ));

  final inner = const Pipeline()
      .addMiddleware(_log())
      .addMiddleware(_cors())
      .addMiddleware(_errors())
      .addMiddleware(_rateLimit(limiter))
      .addHandler(router.call);

  if (webBuildDir == null) {
    return (Request request) => inner(request);
  }

  final webHandler =
      createStaticHandler(webBuildDir.path, defaultDocument: 'index.html');
  final indexHtml = _readIndexHtml(webBuildDir);
  return (Request request) {
    final path = request.url.path;
    if (path == 'health' || path.startsWith('api')) {
      return inner(request);
    }
    return _serveWeb(request, webHandler, indexHtml);
  };
}

List<int> _readIndexHtml(Directory webBuildDir) {
  final index = File('${webBuildDir.path}/index.html');
  if (!index.existsSync()) {
    throw ArgumentError('index.html not found in "${webBuildDir.path}"');
  }
  return index.readAsBytesSync();
}

Future<Response> _serveWeb(
  Request request,
  Handler webHandler,
  List<int> indexHtml,
) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return Response(405, body: 'GET, HEAD');
  }
  final response = await webHandler(request);
  if (response.statusCode == 404 && _isPageRoute(request)) {
    return Response.ok(indexHtml, headers: {'content-type': 'text/html; charset=utf-8'});
  }
  return response;
}

bool _isPageRoute(Request request) {
  final segments = request.url.pathSegments;
  if (segments.isEmpty) {
    return false;
  }
  return !segments.last.contains('.');
}

Future<Response> _findIn(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final area = Area.fromJson(body['area'] as Map<String, dynamic>);
  final result = await networkService.findIn(
    area: area,
    startDate: parseDate(body['startDate']),
    endDate: parseDate(body['endDate']),
    sources: body['sources'] == null
        ? null
        : (body['sources'] as List).cast<String>(),
  );
  return _ok({
    for (final entry in result.entries)
      entry.key: [for (final picture in entry.value) picture.toJson()],
  });
}

Future<Response> _findNear(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final location = Location.fromJson(body['location'] as Map<String, dynamic>);
  final radius = (body['radius'] as num).toDouble();
  final result = await networkService.findNear(
    location: location,
    radius: radius,
    startDate: parseDate(body['startDate']),
    endDate: parseDate(body['endDate']),
    sources: body['sources'] == null
        ? null
        : (body['sources'] as List).cast<String>(),
  );
  return _ok({
    for (final entry in result.entries)
      entry.key: [for (final picture in entry.value) picture.toJson()],
  });
}

Future<Response> _fetchPicture(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final picture = Picture.fromJson(body['picture'] as Map<String, dynamic>);
  final result = await networkService.fetchPicture(picture);
  if (result == null) {
    return Response(404, body: json.encode({'error': 'picture not found'}),
      headers: _jsonHeaders);
  }
  return _ok({'picture': result.toJson()});
}

Future<Response> _searchAddress(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final query = body['query'] as String;
  final result = await networkService.searchAddress(
    query: query,
    source: body['source'] as String?,
  );
  return _ok([for (final place in result) place.toJson()]);
}

Future<Response> _searchCoordinates(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final location = Location.fromJson(body['location'] as Map<String, dynamic>);
  final result = await networkService.searchCoordinates(
    coordinates: location,
    source: body['source'] as String?,
  );
  return _ok([for (final place in result) place.toJson()]);
}

Future<Response> _image(
  Request request,
  NetworkService networkService,
  CachedImageFetcher imageFetcher,
  int maxBodyBytes,
) async {
  final url = request.url.queryParameters['url'];
  if (url == null || url.isEmpty) {
    return Response.badRequest(body: 'Missing "url" query parameter');
  }
  final image = await imageFetcher.fetch(url);
  if (image == null) {
    return Response.notFound('image unavailable');
  }
  final bytes = image.bytes;
  final etag = _etagValue(bytes);
  if (_matchesEtag(request.headers['if-none-match'], etag)) {
    return Response(304, headers: {'etag': etag});
  }
  return Response.ok(
    bytes,
    headers: {
      'content-type': image.contentType ?? 'application/octet-stream',
      'cache-control': 'public, max-age=86400',
      'etag': etag,
    },
  );
}

String _etagValue(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = (hash ^ byte) * 0x01000193 & 0xFFFFFFFF;
  }
  return '"${hash.toRadixString(16)}"';
}

bool _matchesEtag(String? header, String etag) =>
    header != null &&
    header.split(',').any((candidate) {
      final value = candidate.trim();
      return value == etag || value == '*';
    });

Response _ok(Object data) => Response.ok(
  json.encode(data),
  headers: _jsonHeaders,
);

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Future<String> _readBody(Request request, int maxBodyBytes) async {
  final bytes = await request.read().expand((chunk) => chunk).toList();
  final total = bytes.fold<int>(0, (sum, byte) => sum + byte);
  if (total > maxBodyBytes) {
    throw const FormatException('Request body too large');
  }
  return utf8.decode(bytes);
}

Middleware _cors() {
  Map<String, String> headers(Request request) => {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type',
    'Access-Control-Max-Age': '86400',
  };
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers(request));
      }
      final response = await inner(request);
      return response.change(headers: headers(request));
    };
  };
}

Middleware _rateLimit(RateLimiter limiter) {
  return (Handler inner) {
    return (Request request) async {
      if (!limiter.allow(_clientKey(request))) {
        return Response(
          429,
          body: json.encode({'error': 'rate limit exceeded'}),
          headers: _jsonHeaders,
        );
      }
      return inner(request);
    };
  };
}

String _clientKey(Request request) {
  const forwarded = 'x-forwarded-for';
  final upstream = request.headers[forwarded];
  if (upstream != null && upstream.isNotEmpty) {
    return upstream.split(', ').first;
  }
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) {
    return info.remoteAddress.address;
  }
  return 'unknown';
}

Middleware _errors() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on FormatException catch (error) {
        return Response.badRequest(
          body: json.encode({'error': error.message}),
          headers: _jsonHeaders,
        );
      } on DioException catch (error) {
        return Response(
          error.response?.statusCode ?? 502,
          body: json.encode({'error': 'upstream request failed'}),
          headers: _jsonHeaders,
        );
      } on StateError catch (error) {
        return Response.forbidden(json.encode({'error': error.message}),
          headers: _jsonHeaders);
      } catch (_) {
        return Response.internalServerError(
          body: json.encode({'error': 'internal error'}),
          headers: _jsonHeaders,
        );
      }
    };
  };
}

Middleware _log() {
  return (Handler inner) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();
      final response = await inner(request);
      stopwatch.stop();
      print('${request.method} ${request.requestedUri.path} '
          '-> ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
      return response;
    };
  };
}