import 'dart:convert';
import 'dart:io';

/// Server-side settings for the proxy.
///
/// Values are read from a JSON object (by default `server/config.json`) and
/// overridden by process environment variables. Keeping provider client ids
/// and secrets here means the Flutter web build only needs the backend URL.
class ServerConfig {
  ServerConfig(this._values);

  final Map<String, String> _values;

  String operator [](String key) => _values[key] ?? '';

  factory ServerConfig.fromEnvironment() =>
      ServerConfig({...Platform.environment});

  /// Loads [path] (or `CONFIG_FILE`, or the nearest `server/config.json` /
  /// `config.json`) when present.
  ///
  /// Environment variables win, so deployments can keep using secret
  /// environment variables without a file.
  factory ServerConfig.load({String? path}) {
    final environment = Platform.environment;
    final values = <String, String>{};
    final explicit = path ?? environment['CONFIG_FILE'];
    File? file;
    if (explicit != null && explicit.isNotEmpty) {
      file = File(explicit);
      if (!file.existsSync()) {
        throw StateError('CONFIG_FILE "$explicit" does not exist');
      }
    } else {
      // Prefer the server package config so running from the repository root
      // does not accidentally read the Flutter build config.
      for (final candidate in const ['server/config.json', 'config.json']) {
        final candidateFile = File(candidate);
        if (candidateFile.existsSync()) {
          file = candidateFile;
          break;
        }
      }
    }
    if (file != null) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is String && value is String) {
            values[key] = value;
          }
        }
      }
    }
    values.addAll(environment);
    return ServerConfig(values);
  }
}
