import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The session information needed to restore a Google Drive session across
/// app launches, without re-running the OAuth consent flow.
class GoogleDriveSession {
  const GoogleDriveSession({
    required this.refreshToken,
    required this.clientId,
    this.userEmail,
  });

  factory GoogleDriveSession.fromJson(Map<String, Object?> json) {
    return GoogleDriveSession(
      refreshToken: json['refreshToken']! as String,
      clientId: json['clientId']! as String,
      userEmail: json['userEmail'] as String?,
    );
  }

  /// OAuth 2 refresh token that keeps the access token fresh.
  final String refreshToken;

  /// Google Developer Console client identifier the token was issued for.
  final String clientId;

  /// The signed-in account, once known.
  final String? userEmail;

  Map<String, Object?> toJson() => {
        'refreshToken': refreshToken,
        'clientId': clientId,
        'userEmail': userEmail,
      };
}

/// Persists the Google Drive session across app launches so it can be
/// restored without re-running the OAuth consent flow.
abstract class GoogleDriveTokenStore {
  Future<GoogleDriveSession?> read();
  Future<void> write(GoogleDriveSession session);
  Future<void> clear();
}

/// Backs the session with platform secure storage (Keystore / Keychain).
class SecureGoogleDriveTokenStore implements GoogleDriveTokenStore {
  const SecureGoogleDriveTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'google_drive_session';

  final FlutterSecureStorage _storage;

  @override
  Future<GoogleDriveSession?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) {
      return null;
    }
    return GoogleDriveSession.fromJson(
      jsonDecode(stored) as Map<String, Object?>,
    );
  }

  @override
  Future<void> write(GoogleDriveSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}