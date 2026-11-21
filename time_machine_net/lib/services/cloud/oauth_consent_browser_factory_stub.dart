import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';

/// Web has no loopback listener; custom-scheme/browser flows are handled by
/// the supplied browser.
OAuthConsentBrowser createPlatformOAuthConsentBrowser({
  required OAuthConsentBrowser system,
}) =>
    system;
