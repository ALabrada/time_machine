import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The session information needed to restore a Yandex Disk session across
/// app launches, without re-running the OAuth consent flow.
class YandexDiskSession {
  const YandexDiskSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
    this.userEmail,
  });

  factory YandexDiskSession.fromJson(Map<String, Object?> json) {
    return YandexDiskSession(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt']! as String),
      userEmail: json['userEmail'] as String?,
    );
  }

  /// OAuth 2 access token used to authorize every API call.
  final String accessToken;

  /// OAuth 2 refresh token that keeps the access token fresh. Empty for
  /// sessions that were granted without a refresh token.
  final String refreshToken;

  /// When [accessToken] expires, the moment the OAuth server issued it plus
  /// its `expires_in`. `null` when the server reported no lifetime.
  final DateTime? expiresAt;

  /// The signed-in account, once known.
  final String? userEmail;

  YandexDiskSession copy({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? userEmail,
  }) =>
      YandexDiskSession(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
        userEmail: userEmail ?? this.userEmail,
      );

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'userEmail': userEmail,
      };
}

/// Persists the Yandex Disk session across app launches so it can be
/// restored without re-running the OAuth consent flow.
abstract class YandexDiskTokenStore {
  Future<YandexDiskSession?> read();
  Future<void> write(YandexDiskSession session);
  Future<void> clear();
}

/// Backs the session with platform secure storage (Keystore / Keychain).
class SecureYandexDiskTokenStore implements YandexDiskTokenStore {
  const SecureYandexDiskTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'yandex_disk_session';

  final FlutterSecureStorage _storage;

  @override
  Future<YandexDiskSession?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) {
      return null;
    }
    return YandexDiskSession.fromJson(
      jsonDecode(stored) as Map<String, Object?>,
    );
  }

  @override
  Future<void> write(YandexDiskSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}