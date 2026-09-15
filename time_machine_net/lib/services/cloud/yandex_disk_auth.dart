import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/oauth2_client.dart';
// Not exported by `oauth2_client`; imported so tests can substitute their own
// browser lock-in for the authorization-code flow.
// ignore: implementation_imports
import 'package:oauth2_client/src/base_web_auth.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:time_machine_net/services/cloud/yandex_disk_token_store.dart';

/// OAuth 2 client prewired to the Yandex OAuth endpoints
/// (`https://oauth.yandex.ru/`), ready for the authorization-code flow with
/// PKCE that Yandex supports without a client secret.
class YandexDiskAuth extends OAuth2Client {
  YandexDiskAuth({
    String? redirectUri,
    String? customUriScheme,
  }) : super(
          authorizeUrl: 'https://oauth.yandex.ru/authorize',
          tokenUrl: 'https://oauth.yandex.ru/token',
          redirectUri: redirectUri ?? defaultRedirectUri,
          customUriScheme: customUriScheme ?? defaultCustomUriScheme,
          // Yandex expects the client id in the token request body; there is
          // no client secret when PKCE is in use.
          credentialsLocation: CredentialsLocation.body,
        );

  /// App-scoped access to the application's own folder on Yandex Disk
  /// (`/apps/<name>`), allowing read/write exclusively inside it.
  static const cloudApiDiskAppFolderScope = 'cloud_api:disk.app_folder';

  /// Yandex Disk account metadata (login, quota, etc.).
  static const cloudApiDiskInfoScope = 'cloud_api:disk.info';

  static const defaultRedirectUri = 'yandexauth://oauth';
  static const defaultCustomUriScheme = 'yandexauth';

  /// Runs the authorization-code consent flow and maps the response to a
  /// persistable [YandexDiskSession]. Throws when the user cancelled the
  /// dialog or the server denied the request.
  Future<YandexDiskSession> authorize({
    required String clientId,
    List<String> scopes = const [
      cloudApiDiskAppFolderScope,
      cloudApiDiskInfoScope,
    ],
    http.Client? httpClient,
    BaseWebAuth? webAuthClient,
  }) async {
    return _toSession(
      await getTokenWithAuthCodeFlow(
        clientId: clientId,
        scopes: scopes,
        httpClient: httpClient,
        webAuthClient: webAuthClient,
        // Yandex would otherwise silently skip the consent screen for a
        // previously authorized app+account pair and redirect back
        // immediately; force it to always display the page so a fresh
        // authorization is a real login.
        authCodeParams: const {'force_confirm': '1'},
        // Ephemeral Custom Tab on Android (FLAG_ACTIVITY_NO_HISTORY): the tab
        // is not kept in the browser's back stack, so it disappears instead of
        // reopening with an animation after the redirect, and every login
        // runs in a clean browser session with no leftover cookies.
        webAuthOpts: const {'preferEphemeral': true},
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
    final response = await super.refreshToken(
      refreshToken,
      clientId: clientId,
      httpClient: httpClient,
    );
    if (!response.isValid() || response.accessToken == null) {
      return null;
    }
    return _toSession(response);
  }

  YandexDiskSession _toSession(AccessTokenResponse response) {
    if (!response.isValid() ||
        response.accessToken == null ||
        response.accessToken!.isEmpty) {
      throw Exception('Yandex authorization failed');
    }
    return YandexDiskSession(
      accessToken: response.accessToken!,
      refreshToken: response.refreshToken ?? '',
      expiresAt: response.expirationDate,
    );
  }

  /// Runs the Yandex OAuth consent flow entirely in the system browser and
  /// returns the resulting session, without an embedded webview.
  ///
  /// [openBrowser] must hand [authorizationUri] to the platform browser.
  /// [redirectStream] must surface the custom-scheme redirect that the browser
  /// delivers to the app once the user has consented (e.g. from a deep-link
  /// plugin). It is subscribed *before* the browser is opened so a fast
  /// consent redirect is never missed.
  Future<YandexDiskSession> obtainSession({
    required String clientId,
    required void Function(Uri authorizationUri) openBrowser,
    required Stream<Uri> redirectStream,
    List<String> scopes = const [
      cloudApiDiskAppFolderScope,
      cloudApiDiskInfoScope,
    ],
    http.Client? httpClient,
  }) async {
    final codeVerifier = _createCodeVerifier();
    final state = _randomState();
    final authorizationUri = _authorizationUri(
      clientId: clientId,
      scopes: scopes,
      codeVerifier: codeVerifier,
      state: state,
    );

    final redirect =
        await _awaitRedirect(authorizationUri, openBrowser, redirectStream);
    if (redirect.queryParameters['state'] != state) {
      throw StateError('OAuth redirect state mismatch');
    }
    final code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Authorization code missing from the redirect');
    }

    return _toSession(
      await requestAccessToken(
        code: code,
        clientId: clientId,
        codeVerifier: codeVerifier,
        httpClient: httpClient,
      ),
    );
  }

  /// Subscribes to [redirectStream] for a redirect matching [authorizationUri]
  /// and its own expected [redirectUri], then opens the browser. Subscribing
  /// first guarantees the redirect is not missed if the browser returns
  /// quickly.
  Future<Uri> _awaitRedirect(
    Uri authorizationUri,
    void Function(Uri) openBrowser,
    Stream<Uri> redirectStream,
  ) async {
    final completer = Completer<Uri>();
    late StreamSubscription<Uri> subscription;
    final redirect = Uri.parse(redirectUri);
    subscription = redirectStream.listen(
      (uri) {
        if (!completer.isCompleted &&
            uri.scheme == redirect.scheme &&
            uri.host == redirect.host &&
            uri.path == redirect.path &&
            (uri.queryParameters['state'] != null)) {
          completer.complete(uri);
        }
      },
      onError: (Object error, StackTrace _) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );
    try {
      openBrowser(authorizationUri);
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
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
      'code_challenge': _codeChallenge(codeVerifier),
      'code_challenge_method': 'S256',
      'state': state,
      // Yandex would otherwise silently skip the consent screen for a
      // previously authorized app+account pair and redirect back
      // immediately; force it to always present the page so every login is a
      // real authorization.
      'force_confirm': '1',
    };
    return Uri.parse(authorizeUrl).replace(queryParameters: queries);
  }

  static const _verifierCharacters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String _createCodeVerifier() {
    final random = Random.secure();
    return List.generate(64, (_) {
      return _verifierCharacters[random.nextInt(_verifierCharacters.length)];
    }).join();
  }

  static String _codeChallenge(String codeVerifier) {
    final digest = SHA256Digest().process(utf8.encode(codeVerifier));
    return base64Url.encode(digest).replaceAll('=', '');
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(Uint8List.fromList(bytes));
  }
}