import 'dart:async';

import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the OAuth consent page in the system browser and awaits the redirect.
///
/// The browser runs outside the app, so credentials are entered into the
/// browser the user already trusts (including any saved logins). The consent
/// return is delivered back to the app as a deep link on its custom URL
/// scheme; [redirectStream] is that stream (e.g. app_links), merged with the
/// cold-start link so a relaunch never loses the return.
class SystemBrowserOAuthConsentBrowser implements OAuthConsentBrowser {
  SystemBrowserOAuthConsentBrowser({
    required Stream<Uri> Function() redirectStream,
    Future<bool> Function(Uri uri)? launch,
  })  : _redirectStream = redirectStream,
        _launch = launch ?? _launchExternal;

  final Stream<Uri> Function() _redirectStream;
  final Future<bool> Function(Uri uri) _launch;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) {
    final completer = Completer<Uri>();
    StreamSubscription<Uri>? sub;

    // Listen before opening the browser so a fast redirect can't slip by.
    sub = _redirectStream().listen(
      (uri) {
        if (completer.isCompleted || !matchesOAuthRedirect(uri, redirectUri)) {
          return;
        }
        completer.complete(uri);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    completer.future.then(
      (_) => sub?.cancel(),
      onError: (_) => sub?.cancel(),
    );

    _launch(authorizationUri).then(
      (opened) {
        if (!opened && !completer.isCompleted) {
          completer.completeError(
            OAuthConsentCancelledException(
              'Could not open the authorization page in the system browser.',
            ),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    return completer.future;
  }
}