import 'dart:typed_data';

import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:time_machine_cloud/services/cloud/memory_token_stores.dart';
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:time_machine_cloud/services/cloud/oauth_pkce.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_token_store.dart';

/// Runs the Google OAuth consent flow for Drive without Google Play Services.
///
/// Flow: the consent URI is opened in an [OAuthConsentBrowser] (the system
/// browser from `time_machine_net` in the Flutter shell); the user consents;
/// Google redirects back to the app's registered redirect URI, which the
/// operating system delivers to the app as a custom-scheme deep link; the
/// browser resolves with that redirect and returns it here; the code is
/// exchanged for tokens using PKCE.
class GoogleDriveSignIn {
  GoogleDriveSignIn({
    required this.clientId,
    OAuthConsentBrowser? consentBrowser,
    Uri? redirectUri,
    this.hostedDomain,
    http.Client? baseClient,
  })  : consentBrowser = consentBrowser ?? const NoopOAuthConsentBrowser(),
        redirectUri = redirectUri ??
            Uri(scheme: 'com.fakegem.historylens', path: '/oauth2redirect'),
        _baseClient = baseClient;

  /// OAuth 2 client identifier registered for this app.
  final auth.ClientId clientId;

  /// Hosts the consent page and captures the redirect back to [redirectUri],
  /// so the flow needs no system-browser deep links. Defaults to a browser
  /// that throws ([NoopOAuthConsentBrowser]); the widget shell supplies a
  /// real one per call or at construction.
  final OAuthConsentBrowser consentBrowser;

  /// Redirect URI Google sends the browser back to. Defaults to the app's
  /// `com.fakegem.historylens:/oauth2redirect` scheme, which must be
  /// registered in the platform configs (`Info.plist` / Android manifest) and
  /// on the Google Cloud Console OAuth client.
  final Uri redirectUri;

  /// If set, restricts sign-in to Google Workspace accounts hosted at this
  /// domain.
  final String? hostedDomain;

  final http.Client? _baseClient;

  /// The Drive app data scope, matching [GoogleDriveCloud.appDataScope].
  List<String> get scopes => const [GoogleDriveCloud.appDataScope];

  /// Runs the consent flow, persists the resulting session in [tokenStore],
  /// and returns a [GoogleDriveCloud] that restores it when initialized.
  ///
  /// [consentBrowser] must host the consent page in the system browser and
  /// return the redirect Google sends back to the registered URL scheme.
  /// Completes once the code has been exchanged for tokens.
  Future<GoogleDriveCloud> connect({
    OAuthConsentBrowser? consentBrowser,
    String? appRootFolderName,
    Duration pollInterval = const Duration(minutes: 1),
    Uint8List? encryptionKey,
    GoogleDriveTokenStore? tokenStore,
  }) async {
    final store = tokenStore ?? MemoryGoogleDriveTokenStore();
    final session = await obtainSession(consentBrowser: consentBrowser);
    await store.write(session);
    return GoogleDriveCloud(
      client: _baseClient,
      tokenStore: store,
      appRootFolderName: appRootFolderName ?? 'TimeMachine',
      pollInterval: pollInterval,
      encryptionKey: encryptionKey,
    );
  }

  /// Runs the OAuth consent flow and returns a [GoogleDriveSession] without
  /// constructing a new [GoogleDriveCloud]. Used by
  /// [GoogleDriveCloud.authenticate] so the already-configured instance keeps
  /// its own settings and token store.
  Future<GoogleDriveSession> obtainSession({
    OAuthConsentBrowser? consentBrowser,
  }) async {
    final browser = consentBrowser ?? this.consentBrowser;
    final codeVerifier = createPkceCodeVerifier();
    final state = randomOAuthState();
    final authorizationUri = _authorizationUri(
      codeVerifier: codeVerifier,
      state: state,
    );

    final redirect = await browser.consent(
      authorizationUri: authorizationUri,
      redirectUri: redirectUri,
    );
    if (!matchesOAuthRedirect(redirect, redirectUri)) {
      throw StateError('OAuth redirect URI mismatch');
    }
    if (redirect.queryParameters['state'] != state) {
      throw StateError('OAuth redirect state mismatch');
    }
    final code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Authorization code missing from the redirect');
    }

    http.Client client;
    var closeClient = false;
    if (_baseClient != null) {
      client = _baseClient;
    } else {
      client = http.Client();
      closeClient = true;
    }
    final credentials = await auth_io.obtainAccessCredentialsViaCodeExchange(
      client,
      clientId,
      code,
      redirectUrl: redirectUri.toString(),
      codeVerifier: codeVerifier,
    );
    if (closeClient) {
      client.close();
    }

    final refreshToken = credentials.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token returned; cannot keep the session');
    }
    return GoogleDriveSession(
      clientId: clientId.identifier,
      refreshToken: refreshToken,
    );
  }

  /// Persists a [refreshToken] in [tokenStore] and returns a
  /// [GoogleDriveCloud] that restores it when initialized, without prompting
  /// the user again.
  Future<GoogleDriveCloud> connectWithRefreshToken({
    required String refreshToken,
    String? appRootFolderName,
    Duration pollInterval = const Duration(minutes: 1),
    Uint8List? encryptionKey,
    GoogleDriveTokenStore? tokenStore,
  }) async {
    final store = tokenStore ?? MemoryGoogleDriveTokenStore();
    await store.write(GoogleDriveSession(
      clientId: clientId.identifier,
      refreshToken: refreshToken,
    ));
    return GoogleDriveCloud(
      client: _baseClient,
      tokenStore: store,
      appRootFolderName: appRootFolderName ?? 'TimeMachine',
      pollInterval: pollInterval,
      encryptionKey: encryptionKey,
    );
  }

  /// Closes the underlying HTTP client if this instance created one.
  void dispose() {
    _baseClient?.close();
  }

  Uri _authorizationUri({
    required String codeVerifier,
    required String state,
  }) {
    final queries = <String, String>{
      'client_id': clientId.identifier,
      'response_type': 'code',
      'redirect_uri': redirectUri.toString(),
      'scope': scopes.join(' '),
      'code_challenge': pkceCodeChallenge(codeVerifier),
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      if (hostedDomain != null) 'hd': hostedDomain!,
    };
    return const auth.GoogleAuthEndpoints().authorizationEndpoint.replace(
          queryParameters: queries,
        );
  }
}
