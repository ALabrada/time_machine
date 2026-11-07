import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' show DioException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_core/domain/cloud_metadata.dart';
import 'package:time_machine_cloud/services/image_cache.dart';
import 'package:time_machine_cloud/services/network_service.dart';

import 'cloud_cache.dart';
import 'network.dart';
import 'rate_limit.dart';
import 'server_config.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'package:time_machine_cloud/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_cloud/services/cloud/dropbox_cloud.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_cloud.dart';
import 'package:time_machine_cloud/services/cloud_base.dart';
import 'package:time_machine_cloud/services/cloud/oauth_pkce.dart';


class AuthAttempt {
  AuthAttempt({
    required this.provider,
    required this.codeVerifier,
    required this.redirectTo,
    required this.callbackUri,
    required this.expiresAt,
  });
  final String provider;
  final String codeVerifier;
  final String redirectTo;

  /// Absolute redirect URI sent to the provider, captured when the flow
  /// started so the token exchange uses exactly the same value.
  final String callbackUri;
  final DateTime expiresAt;
}
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
  ServerConfig? config,
}) {
  final settings = config ?? ServerConfig.fromEnvironment();
  final cached = imageFetcher ?? CachedImageFetcher();
  final limiter = rateLimiter ?? RateLimiter();

  final Map<String, AuthAttempt> _authAttempts = {};
  void _pruneAttempts() {
    final now = DateTime.now();
    _authAttempts.removeWhere((_, a) => a.expiresAt.isBefore(now));
  }

  // Cloud instances cached for the lifetime of a client's changes websocket.
  // HTTP-only clients get a short-lived instance that is disposed when the
  // request finishes, so idle sessions never accumulate in memory.
  final cloudCache = CloudCache(
    (provider, token, {startPolling = false}) => _createAndInitCloudFull(
      provider,
      token,
      settings: settings,
      startPolling: startPolling,
    ),
  );

  String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

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
    ))
    ..get('/auth/<provider>/start', (Request request) => _authStart(request, _authAttempts, _pruneAttempts, _randomState, settings))
    ..get('/auth/<provider>/callback', (Request request) => _authCallback(request, _authAttempts, _pruneAttempts, settings))
    ..post('/auth/<provider>/refresh', (Request request) => _authRefresh(request, maxBodyBytes, settings))
    ..get('/api/<provider>/me', (Request request) => _apiMe(request, cloudCache))
    ..get('/api/<provider>/records/get', (Request request) => _apiRecordGet(request, cloudCache))
    ..get('/api/<provider>/records/list', (Request request) => _apiRecordList(request, cloudCache))
    ..post('/api/<provider>/records/save', (Request request) => _apiRecordSave(request, maxBodyBytes, cloudCache))
    ..post('/api/<provider>/records/delete', (Request request) => _apiRecordDelete(request, maxBodyBytes, cloudCache))
    ..post('/api/<provider>/files/upload', (Request request) => _apiFileUpload(request, cloudCache))
    ..get('/api/<provider>/files/download', (Request request) => _apiFileDownload(request, cloudCache))
    ..post('/api/<provider>/files/delete', (Request request) => _apiFileDelete(request, maxBodyBytes, cloudCache))
    ..get('/api/<provider>/changes', (Request request) {
      final token = _extractToken(request);
      final provider = request.params['provider'] ?? '';
      return webSocketHandler(
        (WebSocketChannel socket, _) async {
          if (token == null) {
            await socket.sink.close();
            return;
          }
          try {
            // The browser's changes socket anchors a cached cloud: it stays
            // initialized and polling until this socket closes, and HTTP
            // requests from the same browser reuse it.
            final lease = await cloudCache.acquire(
              provider,
              token,
              anchor: true,
            );
            print('WS /api/$provider/changes connected');
            StreamSubscription? sub;
            var stopped = false;
            void stop() {
              if (stopped) return;
              stopped = true;
              sub?.cancel();
              print('WS /api/$provider/changes closed');
              lease.release();
            }

            sub = lease.cloud.changes.listen((event) {
              socket.sink.add(json.encode({'type': event.runtimeType.toString()}));
            });
            socket.stream.listen(
              (_) {},
              onDone: stop,
              onError: (_) => stop(),
            );
          } catch (_) {
            await socket.sink.close();
          }
        },
        // Detect dead browser connections so their cached cloud is released
        // instead of polling forever.
        pingInterval: const Duration(seconds: 30),
      )(request);
    });

  // Providers whose app registration uses a different callback path get an
  // extra route that feeds the same callback handler as
  // `/auth/<provider>/callback`.
  final callbackRoutes = <String, String>{};
  for (final provider in _authProviders) {
    final path = _providerCallbackPath(provider, settings);
    if (path != '/auth/$provider/callback') {
      callbackRoutes[path] = provider;
    }
  }
  for (final entry in callbackRoutes.entries) {
    router.get(
      entry.key,
      (Request request) => _authCallback(
        request,
        _authAttempts,
        _pruneAttempts,
        settings,
        routeProvider: entry.value,
      ),
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

  final webHandler =
      createStaticHandler(webBuildDir.path, defaultDocument: 'index.html');
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
      } on HijackException {
        // WebSocket upgrades escape the pipeline as a HijackException; shelf_io
        // handles it. Converting it to 500 breaks the upgrade.
        rethrow;
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
      } catch (error, stack) {
        print('Unhandled request error: $error\n$stack');
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

const _authProviders = ['gdrive', 'dropbox', 'yandex'];

/// Callback path registered in the provider's app settings, when it differs
/// from the default `/auth/<provider>/callback`.
String _providerCallbackPath(String provider, ServerConfig config) {
  final configured =
      config['${provider.toUpperCase()}_REDIRECT_URI'].trim();
  if (configured.isNotEmpty) {
    final path = Uri.tryParse(configured)?.path;
    if (path != null && path.isNotEmpty) {
      return path;
    }
  }
  return '/auth/$provider/callback';
}

/// The exact redirect URI to send to the provider. It must match one of the
/// URIs registered in the provider's app settings.
String _providerCallbackUri(
  String provider,
  Request request,
  ServerConfig config,
) {
  final configured =
      config['${provider.toUpperCase()}_REDIRECT_URI'].trim();
  if (configured.isNotEmpty) {
    return configured;
  }
  return request.requestedUri
      .resolve(_providerCallbackPath(provider, config))
      .toString();
}

String _buildAuthUrl(String provider, String codeChallenge, String state, String redirectUri, ServerConfig config) {
  final params = <String, String>{
    'client_id': _clientId(provider, config),
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'state': state,
  };
  switch (provider) {
    case 'gdrive':
      params['scope'] = 'https://www.googleapis.com/auth/drive.appdata';
      params['access_type'] = 'offline';
      params['prompt'] = 'consent';
      return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(queryParameters: params).toString();
    case 'dropbox':
      params['token_access_type'] = 'offline';
      params['access_type'] = 'offline';
      params['prompt'] = 'consent';
      return Uri.parse('https://www.dropbox.com/oauth2/authorize').replace(queryParameters: params).toString();
    case 'yandex':
      params['scope'] = 'cloud_api:disk.app_folder cloud_api:disk.info';
      params['force_confirm'] = '1';
      return Uri.parse('https://oauth.yandex.ru/authorize').replace(queryParameters: params).toString();
    default:
      throw ArgumentError('unsupported provider');
  }
}

Future<Map<String, dynamic>> _exchangeCode(String provider, String code, String codeVerifier, String redirectUri, ServerConfig config) {
  return _requestToken(provider, {
    'grant_type': 'authorization_code',
    'code': code,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
  }, config);
}

Future<Map<String, dynamic>> _exchangeRefreshToken(String provider, String refreshToken, ServerConfig config) {
  return _requestToken(provider, {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
  }, config);
}

Future<Map<String, dynamic>> _requestToken(String provider, Map<String, String> body, ServerConfig config) async {
  final client = HttpClient();
  try {
    final tokenUrl = switch (provider) {
      'gdrive' => 'https://oauth2.googleapis.com/token',
      'dropbox' => 'https://api.dropboxapi.com/oauth2/token',
      'yandex' => 'https://oauth.yandex.ru/token',
      _ => throw ArgumentError('unsupported'),
    };
    body['client_id'] = _clientId(provider, config);
    final clientSecret = _clientSecret(provider, config);
    if (clientSecret.isNotEmpty) {
      body['client_secret'] = clientSecret;
    }
    final request = await client.postUrl(Uri.parse(tokenUrl));
    request.headers.set('content-type', 'application/x-www-form-urlencoded');
    request.write(Uri(queryParameters: body).query);
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception(
        'token exchange failed: HTTP ${response.statusCode} $respBody',
      );
    }
    return jsonDecode(respBody) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

String _clientId(String provider, ServerConfig config) {
  final v = config['${provider.toUpperCase()}_CLIENT_ID'];
  if (v.isNotEmpty) return v;
  switch (provider) {
    case 'gdrive':
      return _firstNonEmpty([
        config['GOOGLE_DRIVE_CLIENT_ID_WEB'],
        config['GOOGLE_DRIVE_CLIENT_ID'],
      ]);
    case 'dropbox':
      // The web app's Dropbox key is its OAuth client id.
      return _firstNonEmpty([
        config['DROPBOX_APP_KEY'],
        config['DROPBOX_CLIENT_ID'],
      ]);
    case 'yandex':
      return config['YANDEX_CLIENT_ID'];
  }
  return '';
}

String _clientSecret(String provider, ServerConfig config) {
  final v = config['${provider.toUpperCase()}_CLIENT_SECRET'];
  if (v.isNotEmpty) return v;
  switch (provider) {
    case 'gdrive':
      // The browser flow uses the Web application client, so prefer its
      // secret over the installed-app ones.
      return _firstNonEmpty([
        config['GOOGLE_DRIVE_CLIENT_SECRET_WEB'],
        config['GOOGLE_DRIVE_CLIENT_SECRET'],
      ]);
    case 'dropbox':
      return config['DROPBOX_CLIENT_SECRET'];
    case 'yandex':
      return config['YANDEX_CLIENT_SECRET'];
  }
  return '';
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}

String? _extractToken(Request request) {
  final auth = request.headers['authorization'] ?? request.headers['Authorization'];
  if (auth != null && auth.startsWith('Bearer ')) {
    return auth.substring('Bearer '.length);
  }
  return request.url.queryParameters['access_token'];
}

Future<Map<String, dynamic>> _providerMe(
  String provider,
  String token,
  CloudCache cache,
) async {
  if (provider == 'web') return {'id': '$provider:web'};
  final lease = await cache.acquire(provider, token);
  try {
    return {'id': lease.id};
  } finally {
    lease.release();
  }
}


Future<Response> _authStart(Request request, Map<String, AuthAttempt> attempts, void Function() prune, String Function() randomState, ServerConfig config) async {
  prune();
  final provider = request.params['provider'] ?? '';
  final redirectTo = request.url.queryParameters['redirect_uri'] ?? '';
  if (redirectTo.isEmpty) {
    return Response.badRequest(body: json.encode({'error': 'redirect_uri required'}), headers: _jsonHeaders);
  }
  if (!_authProviders.contains(provider)) {
    return Response.badRequest(body: json.encode({'error': 'unsupported provider'}), headers: _jsonHeaders);
  }
  if (!_isAllowedRedirect(redirectTo, config)) {
    return Response.badRequest(
      body: json.encode({'error': 'redirect_uri not allowed'}),
      headers: _jsonHeaders,
    );
  }
  final codeVerifier = createPkceCodeVerifier();
  final codeChallenge = pkceCodeChallenge(codeVerifier);
  final state = randomState();
  attempts[state] = AuthAttempt(
    provider: provider,
    codeVerifier: codeVerifier,
    redirectTo: redirectTo,
    callbackUri: _providerCallbackUri(provider, request, config),
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  final backendCallback = attempts[state]!.callbackUri;
  final authUrl = _buildAuthUrl(
    provider,
    codeChallenge,
    state,
    backendCallback,
    config,
  );
  return _ok({'authUrl': authUrl});
}

/// Only web app origins may receive the access token after the provider
/// redirects back. Local development origins are always allowed; production
/// deployments must list their origins in `AUTH_REDIRECT_ORIGINS`
/// (comma-separated).
bool _isAllowedRedirect(String value, ServerConfig config) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority) {
    return false;
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    return false;
  }
  final configured = config['AUTH_REDIRECT_ORIGINS'];
  final allowed = configured
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty);
  if (allowed.contains(uri.origin)) {
    return true;
  }
  return uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '::1';
}

Future<Response> _authCallback(
  Request request,
  Map<String, AuthAttempt> attempts,
  void Function() prune,
  ServerConfig config, {
  String? routeProvider,
}) async {
  prune();
  final provider = routeProvider ?? request.params['provider'] ?? '';
  final state = request.url.queryParameters['state'];
  final error = request.url.queryParameters['error'];
  if (error != null && error.isNotEmpty) {
    final attempt = state == null ? null : attempts.remove(state);
    if (attempt == null) {
      return Response.badRequest(body: 'authorization failed: $error');
    }
    return _redirectToApp(attempt.redirectTo, {
      'provider': provider,
      'error': error,
      if (request.url.queryParameters['error_description'] != null)
        'error_description':
            request.url.queryParameters['error_description']!,
    });
  }
  final code = request.url.queryParameters['code'];
  if (code == null || code.isEmpty || state == null || state.isEmpty) {
    return Response.badRequest(body: 'missing code/state');
  }
  final attempt = attempts.remove(state);
  if (attempt == null || attempt.provider != provider || attempt.expiresAt.isBefore(DateTime.now())) {
    return Response(400, body: 'invalid or expired state');
  }
  final backendCallback = attempt.callbackUri;
  final tokens = await _exchangeCode(
    provider,
    code,
    attempt.codeVerifier,
    backendCallback,
    config,
  );
  final expiresIn = tokens['expires_in'];
  final seconds = expiresIn is int ? expiresIn : int.tryParse(expiresIn?.toString() ?? '3600') ?? 3600;
  return _redirectToApp(attempt.redirectTo, {
    'provider': provider,
    'access_token': tokens['access_token'] ?? '',
    if (tokens['refresh_token'] is String &&
        (tokens['refresh_token'] as String).isNotEmpty)
      'refresh_token': tokens['refresh_token'] as String,
    'expires_at': DateTime.now()
        .add(Duration(seconds: seconds))
        .millisecondsSinceEpoch
        .toString(),
  });
}

Response _redirectToApp(String redirectTo, Map<String, String> values) {
  final redirect = Uri.parse(redirectTo);
  final qp = Map<String, String>.from(redirect.queryParameters);
  qp.addAll(values);
  return Response(
    302,
    headers: {'location': redirect.replace(queryParameters: qp).toString()},
  );
}

Future<Response> _authRefresh(Request request, int maxBodyBytes, ServerConfig config) async {
  final provider = request.params['provider'] ?? '';
  if (!_authProviders.contains(provider)) {
    return Response.badRequest(
      body: json.encode({'error': 'unsupported provider'}),
      headers: _jsonHeaders,
    );
  }
  final body = decodeJsonBody(await _readBody(request, maxBodyBytes));
  final refreshToken = body['refresh_token'] as String?;
  if (refreshToken == null || refreshToken.isEmpty) {
    return Response.badRequest(
      body: json.encode({'error': 'refresh_token required'}),
      headers: _jsonHeaders,
    );
  }
  try {
    final tokens = await _exchangeRefreshToken(provider, refreshToken, config);
    return _ok(tokens);
  } catch (_) {
    return Response(
      401,
      body: json.encode({'error': 'refresh failed'}),
      headers: _jsonHeaders,
    );
  }
}

Future<Response> _apiMe(Request request, CloudCache cache) async {
  final provider = request.params['provider'] ?? '';
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  return _ok(await _providerMe(provider, token, cache));
}

Future<Response> _apiRecordGet(Request request, CloudCache cache) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final collection = request.url.queryParameters['collection'] ?? 'records';
  final id = request.url.queryParameters['id'] ?? '';
  CloudLease? lease;
  try {
    lease = await cache.acquire(provider, token);
    final data = await lease.cloud.getRecord(collection, id);
    return _ok({'data': data});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiRecordList(Request request, CloudCache cache) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final collection = request.url.queryParameters['collection'] ?? 'records';
  CloudLease? lease;
  try {
    lease = await cache.acquire(provider, token);
    final items = await lease.cloud.listRecords(collection);
    return _ok({'items': items.map((e) => e.toJson()).toList()});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiRecordSave(
  Request request,
  int maxBodyBytes,
  CloudCache cache,
) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final bodyStr = await _readBody(request, maxBodyBytes);
  final body = decodeJsonBody(bodyStr);
  final collection = body['collection'] as String? ?? 'records';
  final metadata = body['metadata'] as Map<String, dynamic>?;
  final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  CloudLease? lease;
  try {
    lease = await cache.acquire(provider, token);
    final meta = await lease.cloud.saveRecord(
      collection,
      metadata != null ? CloudMetadata.fromJson(metadata) : null,
      data,
    );
    return _ok({'metadata': meta.toJson()});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiRecordDelete(
  Request request,
  int maxBodyBytes,
  CloudCache cache,
) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final bodyStr = await _readBody(request, maxBodyBytes);
  final body = decodeJsonBody(bodyStr);
  final collection = body['collection'] as String? ?? 'records';
  final id = body['id'] as String? ?? '';
  CloudLease? lease;
  try {
    lease = await cache.acquire(provider, token);
    await lease.cloud.deleteRecord(collection, id);
    return _ok({'ok': true});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiFileUpload(Request request, CloudCache cache) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final name = request.url.queryParameters['name'] ?? 'upload';
  final mimeType = request.url.queryParameters['mimeType'];
  CloudLease? lease;
  try {
    final bodyBytes = await request.read().expand((x) => x).toList();
    if (provider == 'web') return _ok({'path': ''});
    lease = await cache.acquire(provider, token);
    final path = await lease.cloud.uploadFile(
      name: name,
      fileData: Uint8List.fromList(bodyBytes),
      mimeType: mimeType,
    );
    return _ok({'path': path});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiFileDownload(Request request, CloudCache cache) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final path = request.url.queryParameters['path'] ?? '';
  CloudLease? lease;
  try {
    if (provider == 'web') {
      return Response.ok([], headers: {'content-type': 'application/octet-stream'});
    }
    lease = await cache.acquire(provider, token);
    final bytes = await lease.cloud.downloadFile(path);
    return Response.ok(bytes, headers: {'content-type': 'application/octet-stream'});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}

Future<Response> _apiFileDelete(
  Request request,
  int maxBodyBytes,
  CloudCache cache,
) async {
  final token = _extractToken(request);
  if (token == null) return Response.unauthorized('missing token');
  final provider = request.params['provider'] ?? '';
  final bodyStr = await _readBody(request, maxBodyBytes);
  final body = decodeJsonBody(bodyStr);
  final path = body['path'] as String? ?? '';
  CloudLease? lease;
  try {
    if (provider == 'web') return _ok({'ok': true});
    lease = await cache.acquire(provider, token);
    await lease.cloud.deleteFile(path);
    return _ok({'ok': true});
  } catch (e) {
    return Response(500, body: e.toString());
  } finally {
    lease?.release();
  }
}



Future<CloudInit> _createAndInitCloudFull(
  String provider,
  String token, {
  required ServerConfig settings,
  bool startPolling = false,
}) async {
  CloudBase? cloud;
  try {
    switch (provider) {
      case 'gdrive':
        final created = GoogleDriveCloud(startPolling: startPolling);
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      case 'dropbox':
        final created = DropBoxCloud(
          clientId: _clientId('dropbox', settings),
          startPolling: startPolling,
        );
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      case 'yandex':
        final created = YandexDiskCloud(
          clientId: _clientId('yandex', settings),
          startPolling: startPolling,
        );
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      default:
        throw ArgumentError('unsupported provider');
    }
  } catch (error, stack) {
    print('Failed to initialize $provider: $error\n$stack');
    cloud?.dispose();
    rethrow;
  }
}

