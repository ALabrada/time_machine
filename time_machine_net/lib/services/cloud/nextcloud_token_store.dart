import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The session information needed to restore a Nextcloud session across app
/// launches, without requiring the user to re-enter their credentials.
class NextcloudSession {
  const NextcloudSession({
    required this.serverUrl,
    required this.loginName,
    required this.password,
    this.userId,
  });

  factory NextcloudSession.fromJson(Map<String, Object?> json) {
    return NextcloudSession(
      serverUrl: json['serverUrl']! as String,
      loginName: json['loginName']! as String,
      password: json['password']! as String,
      userId: json['userId'] as String?,
    );
  }

  /// Base URL of the Nextcloud instance, e.g. `https://cloud.example.com`.
  final String serverUrl;

  /// The user's login name used to authenticate with the instance.
  final String loginName;

  /// The credential sent to the server: either an app password (Bearer) or
  /// the account password (Basic). The cloud tries the app-password (Bearer)
  /// request first and only retries with HTTP Basic if the server returns 401.
  final String password;

  /// The signed-in user's id, once known. Usually equals [loginName].
  final String? userId;

  NextcloudSession copy({
    String? serverUrl,
    String? loginName,
    String? password,
    String? userId,
  }) =>
      NextcloudSession(
        serverUrl: serverUrl ?? this.serverUrl,
        loginName: loginName ?? this.loginName,
        password: password ?? this.password,
        userId: userId ?? this.userId,
      );

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl,
        'loginName': loginName,
        'password': password,
        'userId': userId,
      };
}

/// Persists the Nextcloud session across app launches so it can be restored
/// without re-running the login flow.
abstract class NextcloudTokenStore {
  Future<NextcloudSession?> read();
  Future<void> write(NextcloudSession session);
  Future<void> clear();
}

/// Backs the session with platform secure storage (Keystore / Keychain).
class SecureNextcloudTokenStore implements NextcloudTokenStore {
  const SecureNextcloudTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'nextcloud_session';

  final FlutterSecureStorage _storage;

  @override
  Future<NextcloudSession?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) {
      return null;
    }
    return NextcloudSession.fromJson(
      jsonDecode(stored) as Map<String, Object?>,
    );
  }

  @override
  Future<void> write(NextcloudSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
