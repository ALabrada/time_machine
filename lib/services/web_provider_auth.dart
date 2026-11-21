/// Browser implementation of the backend OAuth flow.
///
/// The proxy backend (`server/`) starts the provider authorization, receives
/// the callback and redirects back to the web app with the tokens. This shell
/// opens the authorization page in a popup and waits for the redirect page
/// (`web/auth.html`) to post it back, so the app itself never leaves the tab.
///
/// The pure-Dart server build must not pull in `package:web`, hence the
/// conditional export: native targets get a stub whose factory throws.
library;

export 'web_provider_auth_stub.dart'
    if (dart.library.js_interop) 'web_provider_auth_web.dart';
