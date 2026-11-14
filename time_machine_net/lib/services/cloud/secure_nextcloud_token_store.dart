import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:time_machine_cloud/time_machine_cloud.dart';

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