import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_auth.dart';

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
        consentBrowser: const _ConsentBrowser(),
        httpClient: http_testing.MockClient(fakeClient),
      );

      expect(session.accessToken, accessToken);
      expect(session.refreshToken, refreshToken);
      expect(session.expiresAt, isNotNull);
      expect(session.expiresAt!.isAfter(DateTime.now()), isTrue);
    });

    test('rejects a state mismatch', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );

      final session = auth.obtainSession(
        clientId: clientId,
        consentBrowser: MemoryOAuthConsentBrowser(
          onConsent: (consentUri) {
            // Return a redirect carrying a *different* state.
            return Uri.parse(auth.redirectUri).replace(
              queryParameters: {'code': code, 'state': 'WRONG_STATE'},
            );
          },
        ),
      );

      await expectLater(session, throwsA(isA<StateError>()));
    });

    test('throws when the redirect lacks a code', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );

      final session = auth.obtainSession(
        clientId: clientId,
        consentBrowser: MemoryOAuthConsentBrowser(
          onConsent: (consentUri) {
            final state = consentUri.queryParameters['state']!;
            return Uri.parse(auth.redirectUri).replace(
              queryParameters: {'state': state},
            );
          },
        ),
      );

      await expectLater(session, throwsA(isA<StateError>()));
    });

    test('consents once with the authorize URL', () async {
      final auth = YandexDiskAuth(
        redirectUri: 'com.fakegem.historylens:/oauth2redirect-yandex',
      );
      final consents = <Uri>[];

      final sessionFuture = auth.obtainSession(
        clientId: clientId,
        consentBrowser: MemoryOAuthConsentBrowser(
          onConsent: (consentUri) {
            consents.add(consentUri);
            final state = consentUri.queryParameters['state']!;
            // Deliver the redirect synchronously (simulates a fast webview).
            return Uri.parse(auth.redirectUri).replace(
              queryParameters: {'code': code, 'state': state},
            );
          },
        ),
        httpClient: http_testing.MockClient((_) async => fakeResponse),
      );

      final session = await sessionFuture;
      expect(consents, hasLength(1));
      expect(session.accessToken, accessToken);
    });
  });
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