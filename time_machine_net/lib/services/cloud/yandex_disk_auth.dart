import 'package:http/http.dart' as http;
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/oauth2_client.dart';
// Not exported by `oauth2_client`; imported so tests can substitute their own
// browser lock-in for the authorization-code flow.
// ignore: implementation_imports
import 'package:oauth2_client/src/base_web_auth.dart';
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

  /// Scope string that unlocks the Yandex Disk API.
  static const cloudApiDiskScope = 'cloud_api:disk';

  static const defaultRedirectUri = 'yandexauth://oauth';
  static const defaultCustomUriScheme = 'yandexauth';

  /// Runs the authorization-code consent flow and maps the response to a
  /// persistable [YandexDiskSession]. Throws when the user cancelled the
  /// dialog or the server denied the request.
  Future<YandexDiskSession> authorize({
    required String clientId,
    List<String> scopes = const [cloudApiDiskScope],
    http.Client? httpClient,
    BaseWebAuth? webAuthClient,
  }) async {
    return _toSession(
      await getTokenWithAuthCodeFlow(
        clientId: clientId,
        scopes: scopes,
        httpClient: httpClient,
        webAuthClient: webAuthClient,
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
}