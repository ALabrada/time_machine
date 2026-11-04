import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:time_machine_cloud/services/cloud/oauth_pkce.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_token_store.dart';

/// OAuth 2 client prewired to the Yandex OAuth endpoints
/// (`https://oauth.yandex.ru/`), ready for the authorization-code flow with
/// PKCE that Yandex supports without a client secret.
///
/// This is a pure-Dart implementation (no `oauth2_client`), so the proxy server
/// can host [YandexDiskCloud] without pulling in Flutter.
class YandexDiskAuth {
  YandexDiskAuth({String? redirectUri})
      : redirectUri = redirectUri ?? defaultRedirectUri;

  static const _authorizeUrl = 'https://oauth.yandex.ru/authorize';
  static const _tokenUrl = 'https://oauth.yandex.ru/token';

  /// App-scoped access to the application's own folder on Yandex Disk
  /// (`/apps/<name>`), allowing read/write exclusively inside it.
  static const cloudApiDiskAppFolderScope = 'cloud_api:disk.app_folder';

  /// Yandex Disk account metadata (login, quota, etc.).
  static const cloudApiDiskInfoScope = 'cloud_api:disk.info';

  static const defaultRedirectUri = 'yandexauth://oauth';

  /// Redirect URI of the registered Yandex OAuth app. The callback scheme
  /// mirrors the redirect URI's scheme, so Yandex can share the common
  /// `com.fakegem.historylens` deep-link scheme and stay unambiguous by
  /// redirect path instead.
  final String redirectUri;

  /// Runs the Yandex OAuth consent flow inside an [OAuthConsentBrowser] (the
  /// system-browser browser from `time_machine_net` in the Flutter shell) and
  /// returns the resulting session.
  ///
  /// [consentBrowser] must host the consent page in the system browser and
  /// return the redirect Yandex sends back to the registered redirect URI once
  /// the user consents (delivered to the app as a deep link).
  Future<YandexDiskSession> obtainSession({
    required String clientId,
    OAuthConsentBrowser? consentBrowser,
    List<String> scopes = const [
      cloudApiDiskAppFolderScope,
      cloudApiDiskInfoScope,
    ],
    http.Client? httpClient,
  }) async {
    final browser = consentBrowser ?? const NoopOAuthConsentBrowser();
    final codeVerifier = createPkceCodeVerifier();
    final state = randomOAuthState();
    final authorizationUri = _authorizationUri(
      clientId: clientId,
      scopes: scopes,
      codeVerifier: codeVerifier,
      state: state,
    );
    final expectedRedirect = Uri.parse(redirectUri);

    final redirect = await browser.consent(
      authorizationUri: authorizationUri,
      redirectUri: expectedRedirect,
    );
    if (!matchesOAuthRedirect(redirect, expectedRedirect)) {
      throw StateError('OAuth redirect URI mismatch');
    }
    if (redirect.queryParameters['state'] != state) {
      throw StateError('OAuth redirect state mismatch');
    }
    final code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Authorization code missing from the redirect');
    }

    return _toSession(
      await _requestToken(
        body: <String, String>{
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': clientId,
          'code_verifier': codeVerifier,
        },
        httpClient: httpClient,
      ),
    );
  }

  /// Exchanges a stored refresh token for a fresh session. Returns `null`
  /// when the server rejected the refresh (revoked/expired refresh token).
  Future<YandexDiskSession?> refresh(
    String refreshToken, {
    required String clientId,
    http.Client? httpClient,
  }) async {
    try {
      final json = await _requestToken(
        body: <String, String>{
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        },
        httpClient: httpClient,
      );
      return _toSession(json);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _requestToken({
    required Map<String, String> body,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client.post(
        Uri.parse(_tokenUrl),
        headers: const {'content-type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Yandex token request failed: HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Yandex token response is not a JSON object');
      }
      return decoded;
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  YandexDiskSession _toSession(Map<String, dynamic> json) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Yandex authorization failed');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    return YandexDiskSession(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Uri _authorizationUri({
    required String clientId,
    required List<String> scopes,
    required String codeVerifier,
    required String state,
  }) {
    final queries = <String, String>{
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'code_challenge': pkceCodeChallenge(codeVerifier),
      'code_challenge_method': 'S256',
      'state': state,
      // Yandex would otherwise silently skip the consent screen for a
      // previously authorized app+account pair and redirect back
      // immediately; force it to always present the page so every login is a
      // real authorization.
      'force_confirm': '1',
    };
    return Uri.parse(_authorizeUrl).replace(queryParameters: queries);
  }
}
