abstract class ProviderAuth {
  Future<ProviderSession?> restore();
  Future<ProviderSession> authenticate();
  Future<void> clear();
}

abstract class ProviderSession {
  String get accountId;
  bool get isExpired;
  Map<String, String> get headers;
}
