import '../server_config.dart';

/// The OAuth client id configured for [provider].
String providerClientId(String provider, ServerConfig config) {
  final value = config['${provider.toUpperCase()}_CLIENT_ID'];
  if (value.isNotEmpty) return value;
  switch (provider) {
    case 'gdrive':
      return _firstNonEmpty([
        config['GOOGLE_DRIVE_CLIENT_ID_WEB'],
        config['GOOGLE_DRIVE_CLIENT_ID'],
      ]);
    case 'dropbox':
      // The web app's Dropbox key is its OAuth client id.
      return _firstNonEmpty([
        config['DROPBOX_APP_KEY'],
        config['DROPBOX_CLIENT_ID'],
      ]);
    case 'yandex':
      return config['YANDEX_CLIENT_ID'];
  }
  return '';
}

/// The OAuth client secret configured for [provider], if any.
String providerClientSecret(String provider, ServerConfig config) {
  final value = config['${provider.toUpperCase()}_CLIENT_SECRET'];
  if (value.isNotEmpty) return value;
  switch (provider) {
    case 'gdrive':
      // The browser flow uses the Web application client, so prefer its secret
      // over the installed-app ones.
      return _firstNonEmpty([
        config['GOOGLE_DRIVE_CLIENT_SECRET_WEB'],
        config['GOOGLE_DRIVE_CLIENT_SECRET'],
      ]);
    case 'dropbox':
      return config['DROPBOX_CLIENT_SECRET'];
    case 'yandex':
      return config['YANDEX_CLIENT_SECRET'];
  }
  return '';
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}
