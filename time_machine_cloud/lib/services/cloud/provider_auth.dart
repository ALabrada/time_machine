abstract class ProviderAuth {
  Future<ProviderSession?> restore();
  Future<ProviderSession> authenticate();
  Future<void> clear();
}

/// An auth flow that can be aborted while [ProviderAuth.authenticate] is still
/// waiting for the user, e.g. when the user cancels an in-app sign-in screen.
abstract interface class CancellableProviderAuth {
  void cancelPending();
}

abstract class ProviderSession {
  String get accountId;
  String get accessToken;
  bool get isExpired;
  Map<String, String> get headers;
}
