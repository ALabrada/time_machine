import 'dart:typed_data';

import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:time_machine_net/services/cloud/google_drive_cloud.dart';

/// Runs the Google OAuth consent flow for Drive without Google Play Services.
///
/// [OpenBrowser] is the only dependency the caller must supply: it receives
/// the Google consent URI and must open it in the system browser / a Chrome
/// Custom Tab, so the loopback redirect (`http://localhost:<port>`) reaches
/// this process again.
class GoogleDriveSignIn {
  GoogleDriveSignIn({
    required this.clientId,
    this.listenPort = 0,
    this.hostedDomain,
    http.Client? baseClient,
  }) : _baseClient = baseClient;

  /// OAuth 2 client identifier registered for this app.
  final auth.ClientId clientId;

  /// Local port used to receive the browser redirect. Use `0` to let the OS
  /// pick an available port.
  final int listenPort;

  /// If set, restricts sign-in to Google Workspace accounts hosted at this
  /// domain.
  final String? hostedDomain;

  final http.Client? _baseClient;

  /// The Drive app data scope, matching [GoogleDriveCloud.appDataScope].
  List<String> get scopes => const [GoogleDriveCloud.appDataScope];

  /// Runs the full consent flow and returns an authenticated
  /// [GoogleDriveCloud] that keeps its access token fresh automatically.
  ///
  /// [openBrowser] must display the consent page in the system browser or a
  /// Chrome Custom Tab. Completes once Google has redirected back to the
  /// locally running loopback server.
  Future<GoogleDriveCloud> connect({
    required void Function(String uri) openBrowser,
    String? appRootFolderName,
    Duration pollInterval = const Duration(minutes: 1),
    Uint8List? encryptionKey,
  }) async {
    final authClient = await auth_io.clientViaUserConsent(
      clientId,
      scopes,
      openBrowser,
      baseClient: _baseClient,
      hostedDomain: hostedDomain,
      listenPort: listenPort,
    );
    return GoogleDriveCloud(
      client: authClient,
      closeClient: true,
      appRootFolderName: appRootFolderName ?? 'TimeMachine',
      pollInterval: pollInterval,
      encryptionKey: encryptionKey,
    );
  }

  /// Restores a session from a persisted [refreshToken] without prompting the
  /// user again.
  Future<GoogleDriveCloud> connectWithRefreshToken({
    required String refreshToken,
    String? appRootFolderName,
    Duration pollInterval = const Duration(minutes: 1),
    Uint8List? encryptionKey,
  }) async {
    final authClient = await auth_io.clientViaRefreshToken(
      clientId,
      refreshToken,
      scopes,
      baseClient: _baseClient,
    );
    return GoogleDriveCloud(
      client: authClient,
      closeClient: true,
      appRootFolderName: appRootFolderName ?? 'TimeMachine',
      pollInterval: pollInterval,
      encryptionKey: encryptionKey,
    );
  }

  /// Closes the underlying HTTP client if this instance created one.
  void dispose() {
    _baseClient?.close();
  }
}