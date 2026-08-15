import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:time_machine_net/services/cloud/google_drive_auth.dart';
import 'package:time_machine_net/services/cloud/google_drive_cloud.dart';

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

      final cloud = await signIn.connect(
        openBrowser: _simulateBrowserRedirect,
      );

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
      final cloud = await signIn.connect(openBrowser: _simulateBrowserRedirect);
      await cloud.initialize();

      final data = Uint8List.fromList([1, 2, 3]);
      await cloud.uploadFile(name: 'hello.txt', fileData: data);

      expect(await cloud.downloadFile('files/hello.txt'), data);

      cloud.dispose();
      signIn.dispose();
    });
  });
}

/// Simulates the browser step of the loopback OAuth flow: extracts the
/// callback URI from the consent URI, then navigates to it with an
/// authorization code and the state, which the locally running loopback
/// server then picks up.
void _simulateBrowserRedirect(String consentUriString) {
  final consentUri = Uri.parse(consentUriString);
  final redirectUri = Uri.parse(consentUri.queryParameters['redirect_uri']!);
  final state = consentUri.queryParameters['state']!;
  final callback = redirectUri.replace(queryParameters: {
    'code': 'granted-code',
    'state': state,
  });
  http.get(callback);
}