import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_net/time_machine_net.dart';

void main() {
  final redirectUri = Uri.parse('com.fakegem.historylens:/oauth2redirect');
  final authorizationUri =
      Uri.parse('https://accounts.google.com/o/oauth2/auth?client_id=x');

  test('launches the browser and returns the matching redirect', () async {
    final redirect =
        redirectUri.replace(queryParameters: {'code': 'abc', 'state': 'xyz'});
    final browser = SystemBrowserOAuthConsentBrowser(
      redirectStream: () => Stream.value(redirect),
      launch: (_) async => true,
    );

    final result = await browser.consent(
      authorizationUri: authorizationUri,
      redirectUri: redirectUri,
    );

    expect(result, redirect);
  });

  test('ignores deep links that do not match the redirect', () async {
    final expected =
        redirectUri.replace(queryParameters: {'code': 'expected'});
    final browser = SystemBrowserOAuthConsentBrowser(
      redirectStream: () => Stream.fromIterable([
        Uri.parse('https://example.com/page?code=wrong'),
        Uri.parse(
          'com.fakegem.historylens:/oauth2redirect-dropbox?code=wrong',
        ),
        expected,
      ]),
      launch: (_) async => true,
    );

    final result = await browser.consent(
      authorizationUri: authorizationUri,
      redirectUri: redirectUri,
    );

    expect(result, expected);
  });

  test('fails when the system browser cannot be opened', () async {
    final browser = SystemBrowserOAuthConsentBrowser(
      redirectStream: () => const Stream<Uri>.empty(),
      launch: (_) async => false,
    );

    await expectLater(
      browser.consent(
        authorizationUri: authorizationUri,
        redirectUri: redirectUri,
      ),
      throwsA(isA<OAuthConsentCancelledException>()),
    );
  });

  test('forwards launch exceptions', () async {
    final browser = SystemBrowserOAuthConsentBrowser(
      redirectStream: () => const Stream<Uri>.empty(),
      launch: (_) async => throw StateError('no browser'),
    );

    await expectLater(
      browser.consent(
        authorizationUri: authorizationUri,
        redirectUri: redirectUri,
      ),
      throwsA(isA<StateError>()),
    );
  });
}