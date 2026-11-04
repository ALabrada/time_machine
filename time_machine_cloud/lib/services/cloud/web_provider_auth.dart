import 'provider_auth.dart';

class WebProviderSession implements ProviderSession {
  WebProviderSession({
    required this.accountId,
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  @override final String accountId;
  final DateTime expiresAt;

  @override bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override Map<String, String> get headers => {
        'Authorization': 'Bearer $accessToken',
      };
}

/// Placeholder for a browser-based provider session.
///
/// The real implementation needs `dart:html` (via `package:web`) and is
/// supplied by the Flutter web shell; the pure-Dart package keeps a
/// behaviourally inert default so it can be imported by the proxy server.
class WebProviderAuth implements ProviderAuth {
  WebProviderAuth({
    required this.providerId,
    required this.backendUrl,
    required this.webAppCallbackUrl,
  });

  final String providerId;
  final Uri backendUrl;
  final String webAppCallbackUrl;

  @override
  Future<ProviderSession?> restore() async => null;

  @override
  Future<ProviderSession> authenticate() async {
    throw UnsupportedError('Web auth requires dart:html');
  }

  @override
  Future<void> clear() async {}
}
