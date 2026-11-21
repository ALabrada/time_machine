import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:time_machine_net/services/cloud/loopback_oauth_consent_browser.dart';

void main() {
  test('captures the loopback redirect and returns its query', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final redirectUri = Uri.parse(
      'http://127.0.0.1:$port/oauth2redirect',
    );

    final browser = LoopbackOAuthConsentBrowser(
      launch: (authorizationUri) async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            redirectUri.replace(
              queryParameters: {'code': 'abc', 'state': 'xyz'},
            ),
          );
          final response = await request.close();
          await response.drain<void>();
        } finally {
          client.close();
        }
        return true;
      },
    );

    final result = await browser.consent(
      authorizationUri: Uri.parse('https://example.com/authorize'),
      redirectUri: redirectUri,
    );

    expect(result.queryParameters['code'], 'abc');
    expect(result.queryParameters['state'], 'xyz');
    expect(matchesOAuthRedirect(result, redirectUri), isTrue);
  });

  test('hybrid browser picks loopback or system by redirect URI', () async {
    final calls = <String>[];
    final system = _RecordingBrowser(calls, 'system');
    final loopback = _RecordingBrowser(calls, 'loopback');
    final browser = HybridOAuthConsentBrowser(
      system: system,
      loopback: loopback,
    );

    await browser.consent(
      authorizationUri: Uri.parse('https://example.com/authorize'),
      redirectUri: Uri.parse('http://127.0.0.1:53682/oauth2redirect'),
    );
    await browser.consent(
      authorizationUri: Uri.parse('https://example.com/authorize'),
      redirectUri: Uri.parse('com.example.app:/oauth2redirect'),
    );

    expect(calls, ['loopback', 'system']);
  });
}

class _RecordingBrowser implements OAuthConsentBrowser {
  _RecordingBrowser(this.calls, this.name);

  final List<String> calls;
  final String name;

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) async {
    calls.add(name);
    return redirectUri;
  }
}
