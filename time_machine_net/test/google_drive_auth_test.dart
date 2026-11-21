import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:time_machine_cloud/services/cloud/google_drive_auth.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_token_store.dart';
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';

import 'fakes/fake_drive_adapter.dart';

void main() {
  final clientId = auth.ClientId('test-id.apps.googleusercontent.com', null);

  group('GoogleDriveSignIn', () {
    test('scopes only grant the Drive app data access', () {
      final signIn = GoogleDriveSignIn(clientId: clientId);
      expect(signIn.scopes, [GoogleDriveCloud.appDataScope]);
      expect(signIn.scopes, [
        'https://www.googleapis.com/auth/drive.appdata',
      ]);
    });

    test('connect runs the consent flow and initializes the cloud', () async {
      final adapter = FakeDriveAdapter();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
      );

      final store = _MemoryTokenStore();
      final cloud = await signIn.connect(
        consentBrowser: const _ConsentBrowser(),
        tokenStore: store,
      );
      expect(store.session, isNotNull);
      expect(store.session!.clientId, clientId.identifier);

      final cloudId = await cloud.initialize();
      expect(cloudId, 'gdrive/user@example.com');
      expect(adapter.exchangedCodes, isNotEmpty);
      expect(
        adapter.authorizationHeaders,
        everyElement('Bearer access-token'),
      );
      cloud.dispose();
      signIn.dispose();
    });

    test('connectWithRefreshToken restores a session silently', () async {
      final adapter = FakeDriveAdapter();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
      );

      final cloud = await signIn.connectWithRefreshToken(
        refreshToken: 'refresh-token',
        tokenStore: _MemoryTokenStore(),
      );

      final cloudId = await cloud.initialize();
      expect(cloudId, 'gdrive/user@example.com');
      expect(adapter.exchangedCodes, isEmpty);
      expect(
        adapter.authorizationHeaders,
        everyElement('Bearer access-token'),
      );
      cloud.dispose();
      signIn.dispose();
    });

    test('connect saves and downloads a record file', () async {
      final adapter = FakeDriveAdapter();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
      );
      final cloud = await signIn.connect(
        consentBrowser: const _ConsentBrowser(),
        tokenStore: _MemoryTokenStore(),
      );
      await cloud.initialize();

      final data = Uint8List.fromList([1, 2, 3]);
      await cloud.uploadFile(name: 'hello.txt', fileData: data);

      expect(await cloud.downloadFile('files/hello.txt'), data);

      cloud.dispose();
      signIn.dispose();
    });
  });
}

class _MemoryTokenStore implements GoogleDriveTokenStore {
  GoogleDriveSession? session;

  @override
  Future<GoogleDriveSession?> read() async => session;

  @override
  Future<void> write(GoogleDriveSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Simulates a user consenting inside the in-app webview: given the
/// authorization URL, it answers with the provider's redirect carrying the
/// same `state` and a fixed authorization code — as if the webview had
/// captured the redirect before it ever left the app.
class _ConsentBrowser implements OAuthConsentBrowser {
  const _ConsentBrowser();

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) async {
    final state = authorizationUri.queryParameters['state']!;
    return redirectUri.replace(queryParameters: {
      'code': 'granted-code',
      'state': state,
    });
  }
}