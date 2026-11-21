import 'dart:async';
import 'dart:io';

import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:url_launcher/url_launcher.dart';

/// Runs the OAuth consent flow with a loopback redirect.
///
/// Google's "Desktop app" OAuth clients require a loopback IP redirect (for
/// example `http://127.0.0.1:53682/oauth2redirect`) rather than a custom URI
/// scheme. The browser opens the consent page and this class listens on the
/// redirect port for the provider's callback.
class LoopbackOAuthConsentBrowser implements OAuthConsentBrowser {
  LoopbackOAuthConsentBrowser({
    Future<bool> Function(Uri uri)? launch,
    this.timeout = const Duration(minutes: 5),
  }) : _launch = launch ?? _launchExternal;

  final Future<bool> Function(Uri uri) _launch;
  final Duration timeout;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) async {
    if (redirectUri.port == 0) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'A loopback redirect URI needs an explicit port',
      );
    }
    final expectedPath = redirectUri.path.isEmpty ? '/' : redirectUri.path;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      redirectUri.port,
    );
    final completer = Completer<Uri>();
    late final StreamSubscription<HttpRequest> subscription;
    subscription = server.listen((request) async {
      if (request.uri.path != expectedPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      try {
        final received = redirectUri.replace(
          queryParameters: request.uri.queryParameters,
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<!doctype html><title>Authentication complete</title>'
            '<p>Authentication is complete. You can close this window and '
            'return to History Lens.</p>',
          );
        await request.response.close();
        if (!completer.isCompleted) {
          completer.complete(received);
        }
      } catch (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          const OAuthConsentCancelledException(
            'The sign-in window timed out',
          ),
        );
      }
    });

    try {
      final opened = await _launch(authorizationUri);
      if (!opened) {
        throw const OAuthConsentCancelledException(
          'Could not open the authorization page in the system browser.',
        );
      }
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
      await server.close(force: true);
    }
  }
}

/// Uses [LoopbackOAuthConsentBrowser] for loopback redirects and the supplied
/// [system] browser for custom-scheme redirects.
class HybridOAuthConsentBrowser implements OAuthConsentBrowser {
  HybridOAuthConsentBrowser({
    required this.system,
    required this.loopback,
  });

  final OAuthConsentBrowser system;
  final OAuthConsentBrowser loopback;

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) {
    final host = redirectUri.host;
    final isLoopback = redirectUri.scheme == 'http' &&
        (host == '127.0.0.1' || host == 'localhost' || host == '::1');
    return (isLoopback ? loopback : system).consent(
      authorizationUri: authorizationUri,
      redirectUri: redirectUri,
    );
  }
}
