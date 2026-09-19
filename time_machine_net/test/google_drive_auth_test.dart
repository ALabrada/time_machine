import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:time_machine_net/services/cloud/google_drive_auth.dart';
import 'package:time_machine_net/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_net/services/cloud/google_drive_token_store.dart';

import 'fakes/fake_drive_adapter.dart';

void main() {
  final clientId = auth.ClientId('test-id.apps.googleusercontent.com', null);

  group('GoogleDriveSignIn', () {
    test('scopes only grant the Drive app data access', () {
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        redirectStream: _emptyStream(),
      );
      expect(signIn.scopes, [GoogleDriveCloud.appDataScope]);
      expect(signIn.scopes, [
        'https://www.googleapis.com/auth/drive.appdata',
      ]);
    });

    test('connect runs the consent flow and initializes the cloud', () async {
      final adapter = FakeDriveAdapter();
      final redirects = _RedirectStream();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
        redirectStream: redirects.stream,
      );

      final store = _MemoryTokenStore();
      final cloud = await signIn.connect(
        openBrowser: redirects.simulateRedirect(signIn),
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
      redirects.close();
    });

    test('connectWithRefreshToken restores a session silently', () async {
      final adapter = FakeDriveAdapter();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
        redirectStream: _emptyStream(),
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
      final redirects = _RedirectStream();
      final signIn = GoogleDriveSignIn(
        clientId: clientId,
        baseClient: adapter.client(),
        redirectStream: redirects.stream,
      );
      final cloud = await signIn.connect(
        openBrowser: redirects.simulateRedirect(signIn),
        tokenStore: _MemoryTokenStore(),
      );
      await cloud.initialize();

      final data = Uint8List.fromList([1, 2, 3]);
      await cloud.uploadFile(name: 'hello.txt', fileData: data);

      expect(await cloud.downloadFile('files/hello.txt'), data);

      cloud.dispose();
      signIn.dispose();
      redirects.close();
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

Stream<Uri> _emptyStream() => const Stream.empty();

/// Simulates the app return leg of the custom-scheme OAuth flow: the
/// `openBrowser` callback opens the consent URI, and the redirect (with the
/// authorization code and the state) is delivered back to [GoogleDriveSignIn]
/// through [stream] — as if iOS/Android had relaunched the app with the custom
/// scheme URL.
class _RedirectStream {
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();

  Stream<Uri> get stream => _controller.stream;

  void Function(Uri consentUri) simulateRedirect(GoogleDriveSignIn signIn) {
    return (consentUri) {
      final state = consentUri.queryParameters['state']!;
      final redirect = signIn.redirectUri.replace(queryParameters: {
        'code': 'granted-code',
        'state': state,
      });
      _controller.add(redirect);
    };
  }

  void close() => _controller.close();
}