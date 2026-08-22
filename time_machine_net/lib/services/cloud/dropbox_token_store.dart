import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The session information needed to restore a Dropbox session across app
/// launches, without re-running the OAuth consent flow.
class DropboxSession {
  const DropboxSession({
    required this.accessToken,
    required this.refreshToken,
    this.accountEmail,
  });

  factory DropboxSession.fromJson(Map<String, Object?> json) {
    return DropboxSession(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken'] as String? ?? '',
      accountEmail: json['accountEmail'] as String?,
    );
  }

  /// OAuth 2 access token used to authorize every API call.
  final String accessToken;

  /// OAuth 2 refresh token that keeps the access token fresh. Empty for
  /// short-lived sessions that were granted without the offline access type.
  final String refreshToken;

  /// The signed-in account, once known.
  final String? accountEmail;

  DropboxSession copy({
    String? accessToken,
    String? refreshToken,
    String? accountEmail,
  }) =>
      DropboxSession(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        accountEmail: accountEmail ?? this.accountEmail,
      );

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accountEmail': accountEmail,
      };
}

/// Persists the Dropbox session across app launches so it can be restored
/// without re-running the OAuth consent flow.
abstract class DropboxTokenStore {
  Future<DropboxSession?> read();
  Future<void> write(DropboxSession session);
  Future<void> clear();
}

/// Backs the session with platform secure storage (Keystore / Keychain).
class SecureDropboxTokenStore implements DropboxTokenStore {
  const SecureDropboxTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'dropbox_session';

  final FlutterSecureStorage _storage;

  @override
  Future<DropboxSession?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) {
      return null;
    }
    return DropboxSession.fromJson(
      jsonDecode(stored) as Map<String, Object?>,
    );
  }

  @override
  Future<void> write(DropboxSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
