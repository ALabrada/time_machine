import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:time_machine_net/services/cloud/yandex_disk_auth.dart';

void main() {
  const clientId = 'test-client-id';
  const code = 'granted-code';
  const accessToken = 'access-token';
  const refreshToken = 'refresh-token';
  const expiresIn = 3600;

  final fakeResponse = http.Response(
    jsonEncode({
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': expiresIn,
    }),
    200,
  );

  group('obtainSession', () {
    test('exchanges the code and returns a session', () async {
      final redirects = _RedirectStream();
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );

      Future<http.Response> fakeClient(http.Request request) async {
        final body = request.body;
        expect(body, contains('grant_type=authorization_code'));
        expect(body, contains('code=granted-code'));
        expect(body, contains('client_id=$clientId'));
        expect(body, contains('code_verifier='));
        return fakeResponse;
      }

      final session = await auth.obtainSession(
        clientId: clientId,
        openBrowser: redirects.simulateRedirect(auth),
        redirectStream: redirects.stream,
        httpClient: http_testing.MockClient(fakeClient),
      );

      expect(session.accessToken, accessToken);
      expect(session.refreshToken, refreshToken);
      expect(session.expiresAt, isNotNull);
      expect(session.expiresAt!.isAfter(DateTime.now()), isTrue);
      redirects.close();
    });

    test('rejects a state mismatch', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );
      final redirects = _RedirectStream();

      final session = auth.obtainSession(
        clientId: clientId,
        openBrowser: (consentUri) {
          // Emit a redirect carrying a *different* state.
          final redirect = Uri.parse(auth.redirectUri).replace(
            queryParameters: {'code': code, 'state': 'WRONG_STATE'},
          );
          redirects._ctrl.add(redirect);
        },
        redirectStream: redirects.stream,
      );

      await expectLater(session, throwsA(isA<StateError>()));
      redirects.close();
    });

    test('throws when the redirect lacks a code', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );
      final redirects = _RedirectStream();

      final session = auth.obtainSession(
        clientId: clientId,
        openBrowser: (consentUri) {
          final state = consentUri.queryParameters['state']!;
          final redirect = Uri.parse(auth.redirectUri).replace(
            queryParameters: {'state': state},
          );
          redirects._ctrl.add(redirect);
        },
        redirectStream: redirects.stream,
      );

      await expectLater(session, throwsA(isA<StateError>()));
      redirects.close();
    });

    test('subscribes before opening the browser', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );
      final redirects = _RedirectStream();
      final opens = <Uri>[];

      final sessionFuture = auth.obtainSession(
        clientId: clientId,
        openBrowser: (consentUri) async {
          opens.add(consentUri);
          final state = consentUri.queryParameters['state']!;
          // Deliver the redirect synchronously (simulates a fast browser).
          redirects._ctrl.add(Uri.parse(auth.redirectUri).replace(
            queryParameters: {'code': code, 'state': state},
          ));
        },
        redirectStream: redirects.stream,
        httpClient: http_testing.MockClient((_) async => fakeResponse),
      );

      final session = await sessionFuture;
      expect(opens, hasLength(1));
      expect(session.accessToken, accessToken);
      redirects.close();
    });
  });
}

class _RedirectStream {
  final StreamController<Uri> _ctrl = StreamController<Uri>.broadcast();

  Stream<Uri> get stream => _ctrl.stream;

  /// Returns an [openBrowser] callback that simulates the user consenting
  /// by emitting the expected redirect (with the correct state) immediately.
  void Function(Uri consentUri) simulateRedirect(YandexDiskAuth auth) {
    return (consentUri) {
      final state = consentUri.queryParameters['state']!;
      final redirect = Uri.parse(auth.redirectUri).replace(
        queryParameters: {'code': 'granted-code', 'state': state},
      );
      _ctrl.add(redirect);
    };
  }

  void close() => _ctrl.close();
}
