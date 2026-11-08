import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_core/services/image_cache.dart';
import 'package:time_machine_sources/services/network_service.dart';
import 'package:time_machine_sources/services/telegram_service.dart';

import 'api/api_utils.dart';
import 'api/cloud_api.dart';
import 'api/network_api.dart';
import 'api/oauth_api.dart';
import 'rate_limit.dart';
import 'server_config.dart';

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
  TelegramPublisher? telegramService,
  CachedImageFetcher? imageFetcher,
  RateLimiter? rateLimiter,
  Directory? webBuildDir,
  int maxBodyBytes = 1 << 20,
  ServerConfig? config,
}) {
  final settings = config ?? ServerConfig.fromEnvironment();
  final cached = imageFetcher ?? CachedImageFetcher();
  final limiter = rateLimiter ?? RateLimiter();

  final networkApi = NetworkApi(
    networkService: networkService,
    maxBodyBytes: maxBodyBytes,
  );
  final oauthApi = OAuthApi(config: settings, maxBodyBytes: maxBodyBytes);
  final cloudApi = CloudApi(settings: settings, maxBodyBytes: maxBodyBytes);

  final router = Router()
    ..get('/health', (Request request) => okResponse({'status': 'ok'}))
    ..post('/api/findIn', networkApi.findIn)
    ..post('/api/findNear', networkApi.findNear)
    ..post('/api/fetchPicture', networkApi.fetchPicture)
    ..post('/api/searchAddress', networkApi.searchAddress)
    ..post('/api/searchCoordinates', networkApi.searchCoordinates)
    ..get('/api/image', (Request request) => _image(request, cached))
    ..post(
      '/api/telegram/submit',
      (Request request) =>
          _telegramSubmit(request, telegramService, telegramMaxBodyBytes),
    )
    ..get('/auth/<provider>/start', oauthApi.start)
    ..get(
      '/auth/<provider>/callback',
      (Request request) => oauthApi.callback(request),
    )
    ..post('/auth/<provider>/refresh', oauthApi.refresh)
    ..get('/api/<provider>/me', cloudApi.me)
    ..get('/api/<provider>/records/get', cloudApi.recordGet)
    ..get('/api/<provider>/records/list', cloudApi.recordList)
    ..post('/api/<provider>/records/save', cloudApi.recordSave)
    ..post('/api/<provider>/records/delete', cloudApi.recordDelete)
    ..post('/api/<provider>/files/upload', cloudApi.fileUpload)
    ..get('/api/<provider>/files/download', cloudApi.fileDownload)
    ..post('/api/<provider>/files/delete', cloudApi.fileDelete)
    ..get('/api/<provider>/changes', cloudApi.changes);

  // Providers whose app registration uses a different callback path get an
  // extra route that feeds the same callback handler as
  // `/auth/<provider>/callback`.
  final callbackRoutes = oauthApi.callbackRoutes;
  for (final entry in callbackRoutes.entries) {
    router.get(
      entry.key,
      (Request request) =>
          oauthApi.callback(request, routeProvider: entry.value),
    );
  }

  final inner = const Pipeline()
      .addMiddleware(_log())
      .addMiddleware(_cors())
      .addMiddleware(_errors())
      .addMiddleware(_rateLimit(limiter))
      .addHandler(router.call);

  if (webBuildDir == null) {
    return (Request request) => inner(request);
  }

  final webHandler = createStaticHandler(
    webBuildDir.path,
    defaultDocument: 'index.html',
  );
  final indexHtml = _readIndexHtml(webBuildDir);
  final callbackPaths = callbackRoutes.keys
      .map((path) => path.startsWith('/') ? path.substring(1) : path)
      .toSet();
  return (Request request) {
    final path = request.url.path;
    if (path == 'health' ||
        path == 'api' ||
        path.startsWith('api/') ||
        path == 'auth' ||
        path.startsWith('auth/') ||
        callbackPaths.contains(path)) {
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
    return Response.ok(
      indexHtml,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
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

/// Pictures may be sent as inline `data:` URLs from the web app, which are
/// considerably larger than the regular JSON bodies handled by the other API
/// routes.
const telegramMaxBodyBytes = 32 << 20;

Future<Response> _telegramSubmit(
  Request request,
  TelegramPublisher? telegram,
  int maxBodyBytes,
) async {
  if (telegram == null || !telegram.enabled) {
    return jsonError(503, 'telegram not configured');
  }
  final body = decodeJsonBody(await readBody(request, maxBodyBytes));
  final rawPictures = body['pictures'];
  if (rawPictures is! List || rawPictures.isEmpty) {
    return jsonError(400, 'pictures required');
  }
  final pictures = [
    for (final item in rawPictures)
      Picture.fromJson(item as Map<String, dynamic>),
  ];
  final submitted = await telegram.submit(
    pictures: pictures,
    caption: body['caption'] as String?,
  );
  return okResponse({'submitted': submitted});
}

Future<Response> _image(
  Request request,
  CachedImageFetcher imageFetcher,
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

Middleware _cors() {
  Map<String, String> headers(Request request) => {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, content-type',
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
        return jsonError(429, 'rate limit exceeded');
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
      } on HijackException {
        // WebSocket upgrades escape the pipeline as a HijackException; shelf_io
        // handles it. Converting it to 500 breaks the upgrade.
        rethrow;
      } on FormatException catch (error) {
        return jsonError(400, error.message);
      } on DioException catch (error) {
        return jsonError(
          error.response?.statusCode ?? 502,
          'upstream request failed',
        );
      } on StateError catch (error) {
        return jsonError(403, error.message);
      } catch (error, stack) {
        print('Unhandled request error: $error\n$stack');
        return jsonError(500, 'internal error');
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
      print(
        '${request.method} ${request.requestedUri.path} '
        '-> ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    };
  };
}
