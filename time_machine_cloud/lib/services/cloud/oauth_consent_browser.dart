/// Hosts the OAuth consent page and captures the redirect back to the app.
///
/// The consent page runs in a browser the user already trusts — the system
/// browser on mobile/desktop, a popup/iframe on web — so credentials are never
/// entered inside the app. The redirect returns to the app as a deep link on
/// its custom URL scheme; the browser resolves with that redirect URI so the
/// provider can exchange the code. The platform must additionally feed the
/// deep-link return into [redirectStream]-like wiring (see the system-browser
/// implementation in `time_machine_net`).
///
/// The interface is pure Dart. Pure packages keep the [NoopOAuthConsentBrowser]
/// default below; Flutter shells pass a real browser (the system-browser
/// browser from the `time_machine_net` package).
abstract interface class OAuthConsentBrowser {
  /// Shows [authorizationUri] and awaits the user's consent.
  ///
  /// Resolves with the redirect URL the provider sent the browser back to
  /// once the user has consented (scheme, host and path matching
  /// [redirectUri]). Throws [OAuthConsentCancelledException] when the user
  /// dismisses the consent page before the flow completes.
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  });
}

/// The consent flow was cancelled before the provider redirected back.
class OAuthConsentCancelledException implements Exception {
  const OAuthConsentCancelledException([
    this.message = 'The OAuth consent flow was cancelled',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Compares the scheme, host and path (but not the query) of [uri] against
/// the expected [redirectUri]. Providers double-check the redirect returned
/// by an [OAuthConsentBrowser] against this before exchanging the code.
bool matchesOAuthRedirect(Uri uri, Uri expected) =>
    uri.scheme == expected.scheme &&
    uri.host == expected.host &&
    uri.path == expected.path;

/// Non-functional browser for pure-Dart use: headless servers and tests that
/// never run an interactive flow. Any consent attempt throws
/// [UnsupportedError] explaining that a platform browser is required.
class NoopOAuthConsentBrowser implements OAuthConsentBrowser {
  const NoopOAuthConsentBrowser();

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) async {
    throw UnsupportedError(
      'The OAuth consent flow needs a platform browser. Pass an '
      'OAuthConsentBrowser (e.g. the system-browser browser from '
      'time_machine_net) to open the consent page.',
    );
  }
}

/// An [OAuthConsentBrowser] that answers without any UI: [redirect] returns a
/// fixed URI, or [onConsent] computes one from the consent URL (typically by
/// echoing back its `state` query parameter). Used by tests, scripts and
/// non-interactive shells to simulate a user consenting.
class MemoryOAuthConsentBrowser implements OAuthConsentBrowser {
  MemoryOAuthConsentBrowser({
    Uri? redirect,
    Uri Function(Uri authorizationUri)? onConsent,
  })  : _redirect = redirect,
        _onConsent = onConsent;

  final Uri? _redirect;
  final Uri Function(Uri authorizationUri)? _onConsent;

  @override
  Future<Uri> consent({
    required Uri authorizationUri,
    required Uri redirectUri,
  }) async {
    final onConsent = _onConsent;
    if (onConsent != null) {
      return onConsent(authorizationUri);
    }
    final redirect = _redirect;
    if (redirect != null) {
      return redirect;
    }
    throw StateError(
      'MemoryOAuthConsentBrowser needs `redirect` or `onConsent`',
    );
  }
}