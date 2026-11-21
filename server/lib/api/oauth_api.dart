import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:time_machine_cloud/services/cloud/oauth_pkce.dart';

import '../server_config.dart';
import 'api_utils.dart';
import 'provider_credentials.dart';

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

/// Handles the OAuth consent and token-refresh endpoints.
class OAuthApi {
  OAuthApi({required this.config, required this.maxBodyBytes, Random? random})
    : _random = random ?? Random.secure();

  final ServerConfig config;
  final int maxBodyBytes;
  final Random _random;
  final Map<String, AuthAttempt> _attempts = {};

  /// Callback paths that providers registered differently from
  /// `/auth/<provider>/callback`, mapped to their provider id.
  Map<String, String> get callbackRoutes {
    final routes = <String, String>{};
    for (final provider in _authProviders) {
      final path = _providerCallbackPath(provider, config);
      if (path != '/auth/$provider/callback') {
        routes[path] = provider;
      }
    }
    return routes;
  }

  Future<Response> start(Request request) async {
    _pruneAttempts();
    final provider = request.params['provider'] ?? '';
    final redirectTo = request.url.queryParameters['redirect_uri'] ?? '';
    if (redirectTo.isEmpty) {
      return jsonError(400, 'redirect_uri required');
    }
    if (!_authProviders.contains(provider)) {
      return jsonError(400, 'unsupported provider');
    }
    if (!_isAllowedRedirect(redirectTo, config)) {
      return jsonError(400, 'redirect_uri not allowed');
    }
    final codeVerifier = createPkceCodeVerifier();
    final codeChallenge = pkceCodeChallenge(codeVerifier);
    final state = _randomState();
    _attempts[state] = AuthAttempt(
      provider: provider,
      codeVerifier: codeVerifier,
      redirectTo: redirectTo,
      callbackUri: _providerCallbackUri(provider, request, config),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    final backendCallback = _attempts[state]!.callbackUri;
    final authUrl = _buildAuthUrl(
      provider,
      codeChallenge,
      state,
      backendCallback,
      config,
    );
    return okResponse({'authUrl': authUrl});
  }

  Future<Response> callback(Request request, {String? routeProvider}) async {
    _pruneAttempts();
    final provider = routeProvider ?? request.params['provider'] ?? '';
    final state = request.url.queryParameters['state'];
    final error = request.url.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final attempt = state == null ? null : _attempts.remove(state);
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
    final attempt = _attempts.remove(state);
    if (attempt == null ||
        attempt.provider != provider ||
        attempt.expiresAt.isBefore(DateTime.now())) {
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
    final seconds = expiresIn is int
        ? expiresIn
        : int.tryParse(expiresIn?.toString() ?? '3600') ?? 3600;
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

  Future<Response> refresh(Request request) async {
    final provider = request.params['provider'] ?? '';
    if (!_authProviders.contains(provider)) {
      return jsonError(400, 'unsupported provider');
    }
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final refreshToken = body['refresh_token'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      return jsonError(400, 'refresh_token required');
    }
    try {
      final tokens = await _exchangeRefreshToken(
        provider,
        refreshToken,
        config,
      );
      return okResponse(tokens);
    } catch (_) {
      return jsonError(401, 'refresh failed');
    }
  }

  void _pruneAttempts() {
    final now = DateTime.now();
    _attempts.removeWhere((_, attempt) => attempt.expiresAt.isBefore(now));
  }

  String _randomState() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

const _authProviders = ['gdrive', 'dropbox', 'yandex'];

/// Callback path registered in the provider's app settings, when it differs
/// from the default `/auth/<provider>/callback`.
String _providerCallbackPath(String provider, ServerConfig config) {
  final configured = config['${provider.toUpperCase()}_REDIRECT_URI'].trim();
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
  final configured = config['${provider.toUpperCase()}_REDIRECT_URI'].trim();
  if (configured.isNotEmpty) {
    return configured;
  }
  return request.requestedUri
      .resolve(_providerCallbackPath(provider, config))
      .toString();
}

String _buildAuthUrl(
  String provider,
  String codeChallenge,
  String state,
  String redirectUri,
  ServerConfig config,
) {
  final params = <String, String>{
    'client_id': providerClientId(provider, config),
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
      return Uri.parse(
        'https://accounts.google.com/o/oauth2/v2/auth',
      ).replace(queryParameters: params).toString();
    case 'dropbox':
      params['token_access_type'] = 'offline';
      params['access_type'] = 'offline';
      params['prompt'] = 'consent';
      return Uri.parse(
        'https://www.dropbox.com/oauth2/authorize',
      ).replace(queryParameters: params).toString();
    case 'yandex':
      params['scope'] = 'cloud_api:disk.app_folder cloud_api:disk.info';
      params['force_confirm'] = '1';
      return Uri.parse(
        'https://oauth.yandex.ru/authorize',
      ).replace(queryParameters: params).toString();
    default:
      throw ArgumentError('unsupported provider');
  }
}

Future<Map<String, dynamic>> _exchangeCode(
  String provider,
  String code,
  String codeVerifier,
  String redirectUri,
  ServerConfig config,
) {
  return _requestToken(provider, {
    'grant_type': 'authorization_code',
    'code': code,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
  }, config);
}

Future<Map<String, dynamic>> _exchangeRefreshToken(
  String provider,
  String refreshToken,
  ServerConfig config,
) {
  return _requestToken(provider, {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
  }, config);
}

Future<Map<String, dynamic>> _requestToken(
  String provider,
  Map<String, String> body,
  ServerConfig config,
) async {
  final client = HttpClient();
  try {
    final tokenUrl = switch (provider) {
      'gdrive' => 'https://oauth2.googleapis.com/token',
      'dropbox' => 'https://api.dropboxapi.com/oauth2/token',
      'yandex' => 'https://oauth.yandex.ru/token',
      _ => throw ArgumentError('unsupported'),
    };
    body['client_id'] = providerClientId(provider, config);
    final clientSecret = providerClientSecret(provider, config);
    if (clientSecret.isNotEmpty) {
      body['client_secret'] = clientSecret;
    }
    final request = await client.postUrl(Uri.parse(tokenUrl));
    request.headers.set('content-type', 'application/x-www-form-urlencoded');
    request.write(Uri(queryParameters: body).query);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception(
        'token exchange failed: HTTP ${response.statusCode} $responseBody',
      );
    }
    return jsonDecode(responseBody) as Map<String, dynamic>;
  } finally {
    client.close();
  }
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

Response _redirectToApp(String redirectTo, Map<String, String> values) {
  final redirect = Uri.parse(redirectTo);
  final queryParameters = Map<String, String>.from(redirect.queryParameters);
  queryParameters.addAll(values);
  return Response(
    302,
    headers: {
      'location': redirect.replace(queryParameters: queryParameters).toString(),
    },
  );
}
