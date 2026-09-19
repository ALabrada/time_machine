import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:time_machine_net/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_net/services/cloud/google_drive_token_store.dart';

/// Runs the Google OAuth consent flow for Drive without Google Play Services.
///
/// Flow: a consent URI is handed to [OpenBrowser]; the user consents; Google
/// redirects that browser to a custom URL scheme registered for this app; the
/// app is relaunched/activated with the redirect URI, which flows through
/// [redirectStream] back to this class; the authorization code is exchanged
/// for tokens using PKCE.
class GoogleDriveSignIn {
  GoogleDriveSignIn({
    required this.clientId,
    required this.redirectStream,
    Uri? redirectUri,
    this.hostedDomain,
    http.Client? baseClient,
  })  : redirectUri = redirectUri ??
            Uri(scheme: 'com.fakegem.historylens', path: '/oauth2redirect'),
        _baseClient = baseClient;

  /// OAuth 2 client identifier registered for this app.
  final auth.ClientId clientId;

  /// Stream of custom-scheme URLs delivered to the app (deep links). The
  /// stream must be broadcast-friendly: it is subscribed before the browser is
  /// opened, and must surface the Google redirect (e.g. from a deep-link
  /// plugin) once the user has consented.
  final Stream<Uri> redirectStream;

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
  /// [openBrowser] must display the consent page in the system browser or a
  /// Chrome Custom Tab. Completes once Google has redirected back to the
  /// registered URL scheme and the code has been exchanged for tokens.
  Future<GoogleDriveCloud> connect({
    required void Function(Uri authorizationUri) openBrowser,
    String? appRootFolderName,
    Duration pollInterval = const Duration(minutes: 1),
    Uint8List? encryptionKey,
    GoogleDriveTokenStore? tokenStore,
  }) async {
    final store = tokenStore ?? const SecureGoogleDriveTokenStore();
    final session = await obtainSession(openBrowser: openBrowser);
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
    required void Function(Uri authorizationUri) openBrowser,
  }) async {
    final codeVerifier = _createCodeVerifier();
    final state = _randomState();
    final authorizationUri = _authorizationUri(
      codeVerifier: codeVerifier,
      state: state,
    );

    final redirect = await _awaitRedirect(authorizationUri, openBrowser);
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
    final store = tokenStore ?? const SecureGoogleDriveTokenStore();
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

  /// Subscribes to [redirectStream] for a redirect matching [authorizationUri],
  /// then opens the consent page. Subscribing first guarantees the redirect is
  /// not missed if the browser returns quickly.
  Future<Uri> _awaitRedirect(
    Uri authorizationUri,
    void Function(Uri) openBrowser,
  ) async {
    final completer = Completer<Uri>();
    late StreamSubscription<Uri> subscription;
    subscription = redirectStream.listen(
      (uri) {
        if (!completer.isCompleted &&
            uri.scheme == redirectUri.scheme &&
            uri.host == redirectUri.host &&
            uri.path == redirectUri.path &&
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
    required String codeVerifier,
    required String state,
  }) {
    final queries = <String, String>{
      'client_id': clientId.identifier,
      'response_type': 'code',
      'redirect_uri': redirectUri.toString(),
      'scope': scopes.join(' '),
      'code_challenge': _codeChallenge(codeVerifier),
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      if (hostedDomain != null) 'hd': hostedDomain!,
    };
    return const auth.GoogleAuthEndpoints().authorizationEndpoint.replace(
          queryParameters: queries,
        );
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
