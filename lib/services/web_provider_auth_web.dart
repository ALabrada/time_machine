import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:time_machine_cloud/time_machine_cloud.dart';
import 'package:web/web.dart' as web;

/// Creates the browser OAuth session helper used by the web build.
ProviderAuth createWebProviderAuth({
  required String providerId,
  required Uri backendUrl,
  String? clientId,
}) =>
    BrowserProviderAuth(
      providerId: providerId,
      backendUrl: backendUrl,
      clientId: clientId,
    );

/// Runs the backend-mediated OAuth flow from the browser.
///
/// `GET {backend}/auth/{provider}/start?redirect_uri=...` returns the provider
/// authorization URL. It is opened in a popup; the provider redirects to the
/// backend callback, which redirects to `web/auth.html` with the tokens. That
/// page posts the redirect URL back to this window, where the tokens are
/// stored in `localStorage` and handed to [BackendProxyCloud].
class BrowserProviderAuth implements ProviderAuth, CancellableProviderAuth {
  BrowserProviderAuth({
    required this.providerId,
    required this.backendUrl,
    this.clientId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String providerId;
  final Uri backendUrl;

  /// The provider application ID to authorize with. The backend falls back to
  /// its own `*_CLIENT_ID` environment variables when this is empty.
  final String? clientId;
  final http.Client _http;

  static final _random = Random.secure();

  /// The awaiting popup flow, when one is in progress, so an in-app cancel can
  /// end it without waiting for the timeout.
  Completer<Uri>? _pendingRedirect;

  /// Set by [cancelPending] so a cancel that arrives while the backend start
  /// request is still in flight aborts as soon as that request returns.
  bool _cancelled = false;

  String get _storageKey => 'historylens.oauth.$providerId';

  @override
  Future<ProviderSession?> restore() async {
    final stored = _readSession();
    if (stored == null) {
      return null;
    }
    if (!stored.isExpired) {
      return stored;
    }
    final refreshToken = stored.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      final refreshed = await _refresh(refreshToken);
      if (refreshed != null) {
        _writeSession(refreshed);
        return refreshed;
      }
    }
    _clearSession();
    return null;
  }

  @override
  Future<ProviderSession> authenticate() async {
    _cancelled = false;
    final nonce = _randomNonce();
    final callback = _callbackUri(nonce);
    final startUri = backendUrl.replace(
      path: '/auth/$providerId/start',
      queryParameters: {
        'redirect_uri': callback.toString(),
        if (clientId != null && clientId!.isNotEmpty) 'client_id': clientId!,
      },
    );
    // Open the window before awaiting the backend. Browsers only allow a
    // popup while the click that started the flow still counts as a user
    // gesture, and a slow backend round trip can outlive it.
    final popup = web.window.open(
      '',
      'historylens_oauth_$providerId',
      'popup=yes,width=520,height=720',
    );
    if (popup == null) {
      throw StateError(
        'The sign-in popup was blocked. Allow popups for this site and try '
        'again.',
      );
    }
    try {
      final start = await _http.get(startUri);
      if (_cancelled) {
        throw const OAuthSignInCancelledException();
      }
      if (start.statusCode != 200) {
        throw Exception(
          'Sign-in could not be started (HTTP ${start.statusCode}): '
          '${start.body}',
        );
      }
      final decoded = jsonDecode(start.body);
      final authUrl = decoded is Map ? decoded['authUrl'] as String? : null;
      if (authUrl == null || authUrl.isEmpty) {
        throw Exception('The backend did not return an authorization URL');
      }
      if (_cancelled) {
        throw const OAuthSignInCancelledException();
      }

      popup.location.href = authUrl;
      final redirect = await _waitForRedirect(nonce, popup);
      final session = _sessionFromRedirect(redirect);
      _writeSession(session);
      return session;
    } catch (_) {
      popup.close();
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    _clearSession();
  }

  @override
  void cancelPending() {
    _cancelled = true;
    final pending = _pendingRedirect;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const OAuthSignInCancelledException());
    }
  }

  Uri _callbackUri(String nonce) {
    final base = Uri.base.resolve('auth.html');
    return base.replace(
      queryParameters: {...base.queryParameters, 'nonce': nonce},
    );
  }

  Future<Uri> _waitForRedirect(String nonce, web.Window popup) async {
    final completer = Completer<Uri>();
    late final JSFunction listener;

    void onMessage(web.Event event) {
      final message = event as web.MessageEvent;
      final data = message.data.dartify();
      if (data is! Map) {
        return;
      }
      final href = data['flutter-web-auth-2'];
      if (href is! String) {
        return;
      }
      final uri = Uri.tryParse(href);
      if (uri == null || uri.queryParameters['nonce'] != nonce) {
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(uri);
      }
    }

    listener = onMessage.toJS;
    web.window.addEventListener('message', listener);
    _pendingRedirect = completer;
    if (_cancelled) {
      completer.completeError(const OAuthSignInCancelledException());
    }

    // When the provider (or its consent page) severs `window.opener`, the
    // callback page stores the redirect here instead of messaging us.
    Uri? takeStoredRedirect() {
      final raw = web.window.localStorage.getItem('flutter-web-auth-2');
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.queryParameters['nonce'] != nonce) {
        return null;
      }
      web.window.localStorage.removeItem('flutter-web-auth-2');
      return uri;
    }

    final stored = takeStoredRedirect();
    if (stored != null && !completer.isCompleted) {
      completer.complete(stored);
    }

    // The callback page can be in a different browsing context group because
    // providers such as Dropbox send COOP; that severs `window.opener`, so the
    // callback can only leave the redirect in localStorage. Poll for it.
    // `window.closed` cannot be trusted once the popup is cross-origin (it
    // reads true while the popup is still open), so a user who closes the
    // popup cancels the wait through the in-app cancel action instead.
    final pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final stored = takeStoredRedirect();
      if (stored != null && !completer.isCompleted) {
        completer.complete(stored);
      }
    });
    final timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'The sign-in window timed out',
            const Duration(minutes: 5),
          ),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      web.window.removeEventListener('message', listener);
      pollTimer.cancel();
      timeoutTimer.cancel();
      if (identical(_pendingRedirect, completer)) {
        _pendingRedirect = null;
      }
      popup.close();
    }
  }

  WebProviderSession _sessionFromRedirect(Uri redirect) {
    final params = redirect.queryParameters;
    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      final description = params['error_description'];
      throw Exception(
        description == null || description.isEmpty
            ? 'Sign-in failed: $error'
            : 'Sign-in failed: $error ($description)',
      );
    }
    final accessToken = params['access_token'];
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Sign-in did not return an access token');
    }
    final expiresAtMillis = int.tryParse(params['expires_at'] ?? '');
    final expiresAt = expiresAtMillis == null
        ? DateTime.now().add(const Duration(hours: 1))
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis);
    final refreshToken = params['refresh_token'];
    return WebProviderSession(
      accountId: providerId,
      accessToken: accessToken,
      refreshToken:
          refreshToken == null || refreshToken.isEmpty ? null : refreshToken,
      expiresAt: expiresAt,
    );
  }

  Future<WebProviderSession?> _refresh(String refreshToken) async {
    final uri = backendUrl.replace(path: '/auth/$providerId/refresh');
    try {
      final response = await _http.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'refresh_token': refreshToken,
          if (clientId != null && clientId!.isNotEmpty) 'client_id': clientId,
        }),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      final refreshedToken = json['refresh_token'] as String?;
      return WebProviderSession(
        accountId: providerId,
        accessToken: accessToken,
        refreshToken: refreshedToken == null || refreshedToken.isEmpty
            ? refreshToken
            : refreshedToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
    } catch (_) {
      return null;
    }
  }

  WebProviderSession? _readSession() {
    final raw = web.window.localStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      final expiresAt = (json['expires_at'] as num?)?.toInt();
      if (accessToken == null || accessToken.isEmpty || expiresAt == null) {
        return null;
      }
      return WebProviderSession(
        accountId: json['account_id'] as String? ?? providerId,
        accessToken: accessToken,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      );
    } catch (_) {
      return null;
    }
  }

  void _writeSession(WebProviderSession session) {
    web.window.localStorage.setItem(
      _storageKey,
      jsonEncode({
        'account_id': session.accountId,
        'access_token': session.accessToken,
        'refresh_token': session.refreshToken,
        'expires_at': session.expiresAt.millisecondsSinceEpoch,
      }),
    );
  }

  void _clearSession() {
    web.window.localStorage.removeItem(_storageKey);
  }

  String _randomNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The user cancelled the sign-in before the provider redirected back.
class OAuthSignInCancelledException implements Exception {
  const OAuthSignInCancelledException([
    this.message = 'Sign-in was cancelled',
  ]);

  final String message;

  @override
  String toString() => message;
}
