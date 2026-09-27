import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/oauth2_client.dart';
// Not exported by `oauth2_client`; imported so tests can substitute their own
// browser lock-in for the authorization-code flow.
// ignore: implementation_imports
import 'package:oauth2_client/src/base_web_auth.dart';
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:time_machine_cloud/services/cloud/oauth_pkce.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_token_store.dart';

/// OAuth 2 client prewired to the Yandex OAuth endpoints
/// (`https://oauth.yandex.ru/`), ready for the authorization-code flow with
/// PKCE that Yandex supports without a client secret.
class YandexDiskAuth extends OAuth2Client {
  YandexDiskAuth({String? redirectUri}) : super(
          authorizeUrl: 'https://oauth.yandex.ru/authorize',
          tokenUrl: 'https://oauth.yandex.ru/token',
          redirectUri: redirectUri ?? defaultRedirectUri,
          // The callback scheme always mirrors the redirect URI's scheme, so
          // Yandex can share the common `com.fakegem.historylens` deep-link
          // scheme and stay unambiguous by redirect path instead.
          customUriScheme:
              Uri.parse(redirectUri ?? defaultRedirectUri).scheme,
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
      await requestAccessToken(
        code: code,
        clientId: clientId,
        codeVerifier: codeVerifier,
        httpClient: httpClient,
      ),
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
    return Uri.parse(authorizeUrl).replace(queryParameters: queries);
  }
}