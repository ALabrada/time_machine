/// Third-party credentials injected at build time.
///
/// Values are supplied through
/// `flutter run/build --dart-define-from-file=config.json` (see
/// `config.example.json` for the key list). Any key missing from the config
/// file becomes an empty string, so consumers check the value before enabling
/// the feature that needs it:
///  * no `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHANNEL_ID` -> the Telegram share
///    option is not shown on native builds; the web build uses
///    `BACKEND_TELEGRAM` instead, so the bot token never reaches the browser;
///  * no Google Drive client id for the current platform -> Google Drive is not
///    offered as a cloud provider;
///  * no `DROPBOX_APP_KEY`/`YANDEX_CLIENT_ID` -> the corresponding cloud
///    providers are not offered;
///  * no `VK_MAPS_API_KEY` -> the VKMaps geocoder is not offered (the VK
///    vector tile server stays selectable but fails gracefully when used).
///
/// Client secrets are deliberately not part of this file for OAuth providers
/// whose token exchange runs on the proxy server: they must stay server-side
/// (environment variables), never in a web build.
library;

// Names mirror the `config.json` define keys, so they intentionally break the
// lowerCamelCase rule.
// ignore_for_file: constant_identifier_names

const String GOOGLE_DRIVE_CLIENT_ID_DESKTOP =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID_DESKTOP');
const String GOOGLE_DRIVE_CLIENT_ID_IOS =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID_IOS');
const String GOOGLE_DRIVE_CLIENT_ID_ANDROID =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID_ANDROID');

/// Installed-app client secret. Desktop OAuth clients may require it; it is
/// embedded in the native binary, which is normal for installed apps.
const String GOOGLE_DRIVE_CLIENT_SECRET_DESKTOP =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_SECRET_DESKTOP');

const String DROPBOX_APP_KEY = String.fromEnvironment('DROPBOX_APP_KEY');
const String YANDEX_CLIENT_ID = String.fromEnvironment('YANDEX_CLIENT_ID');

const String TELEGRAM_BOT_TOKEN = String.fromEnvironment('TELEGRAM_BOT_TOKEN');
const String TELEGRAM_CHANNEL_ID =
    String.fromEnvironment('TELEGRAM_CHANNEL_ID');

const String VK_MAPS_API_KEY = String.fromEnvironment('VK_MAPS_API_KEY');

/// URL of the proxy backend (the `server/` package). When non-empty and the
/// app runs on the web, outbound photo/geocoding traffic is routed through it
/// (the browser itself cannot talk to provider servers due to CORS); on
/// native platforms the direct providers are used regardless.
const String BACKEND_URL = String.fromEnvironment('BACKEND_URL');

/// Comma-separated cloud providers the proxy backend has credentials for
/// (for example `gdrive,dropbox,yandex`). Empty means all backend providers.
/// This is build-time configuration, like [BACKEND_URL]; it is not a secret.
const String BACKEND_PROVIDERS =
    String.fromEnvironment('BACKEND_PROVIDERS');

/// Whether the proxy backend has Telegram publishing configured. Like
/// [BACKEND_PROVIDERS], this only tells the frontend which backend features to
/// offer; the bot token itself stays on the server.
const bool BACKEND_TELEGRAM = bool.fromEnvironment('BACKEND_TELEGRAM');

/// OAuth consent return URIs. Registered in the OAuth provider apps and in
/// the platform URL schemes; public application configuration, not secrets.
const String GOOGLE_DRIVE_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect';

/// Loopback redirect used by Google's "Desktop app" OAuth client. Desktop
/// clients do not accept the mobile custom scheme; Google recommends a
/// loopback URI and accepts any port without registering it.
const String GOOGLE_DRIVE_DESKTOP_REDIRECT_URI = String.fromEnvironment(
  'GOOGLE_DRIVE_DESKTOP_REDIRECT_URI',
  defaultValue: 'http://127.0.0.1:53682/oauth2redirect',
);
const String DROPBOX_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect-dropbox';
const String YANDEX_REDIRECT_URI =
    'com.fakegem.historylens:/oauth2redirect-yandex';

/// Telegram bot API key for native builds, or null when not configured.
///
/// Web builds never read the bot token: they publish through the proxy
/// backend, which reads it from its own configuration.
String? get telegramBotToken => _present(TELEGRAM_BOT_TOKEN);

/// Numeric Telegram channel id for native builds, or null when not configured.
int? get telegramChannelId => int.tryParse(TELEGRAM_CHANNEL_ID);

String? _present(String value) => value.isEmpty ? null : value;