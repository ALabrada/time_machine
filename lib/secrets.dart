/// Third-party credentials injected at build time.
///
/// Values are supplied through
/// `flutter run/build --dart-define-from-file=config.json` (see
/// `config.example.json` for the key list). Any key missing from the config
/// file becomes an empty string, so consumers check the value before enabling
/// the feature that needs it:
///  * no `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHANNEL_ID` -> the Telegram share
///    option is not shown;
///  * no `GOOGLE_DRIVE_CLIENT_ID_IOS`/`_ANDROID` -> Google Drive is not
///    offered as a cloud provider;
///  * no `DROPBOX_APP_KEY`/`YANDEX_CLIENT_ID` -> the corresponding cloud
///    providers are not offered;
///  * no `VK_MAPS_API_KEY` -> the VKMaps geocoder is not offered (the VK
///    vector tile server stays selectable but fails gracefully when used).
library;

// Names mirror the `config.json` define keys, so they intentionally break the
// lowerCamelCase rule.
// ignore_for_file: constant_identifier_names

const String GOOGLE_DRIVE_CLIENT_ID_IOS =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID_IOS');
const String GOOGLE_DRIVE_CLIENT_ID_ANDROID =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID_ANDROID');
const String DROPBOX_APP_KEY = String.fromEnvironment('DROPBOX_APP_KEY');
const String YANDEX_CLIENT_ID = String.fromEnvironment('YANDEX_CLIENT_ID');

const String TELEGRAM_BOT_TOKEN = String.fromEnvironment('TELEGRAM_BOT_TOKEN');
const String TELEGRAM_CHANNEL_ID =
    String.fromEnvironment('TELEGRAM_CHANNEL_ID');

const String VK_MAPS_API_KEY = String.fromEnvironment('VK_MAPS_API_KEY');

/// OAuth consent return URIs. Registered in the OAuth provider apps and in
/// the platform URL schemes; public application configuration, not secrets.
const String GOOGLE_DRIVE_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect';
const String DROPBOX_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect-dropbox';
const String YANDEX_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect-yandex';

/// Telegram bot API key, or null when not configured.
String? get telegramBotToken => _present(TELEGRAM_BOT_TOKEN);

/// Numeric Telegram channel id, or null when not configured.
int? get telegramChannelId => int.tryParse(TELEGRAM_CHANNEL_ID);

String? _present(String value) => value.isEmpty ? null : value;