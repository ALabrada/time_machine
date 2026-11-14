import 'package:time_machine_cloud/services/cloud/oauth_consent_browser.dart';

import 'loopback_oauth_consent_browser.dart';

/// Native platforms can use a loopback redirect for Google's Desktop OAuth
/// client; custom-scheme providers keep using [system].
OAuthConsentBrowser createPlatformOAuthConsentBrowser({
  required OAuthConsentBrowser system,
}) =>
    HybridOAuthConsentBrowser(
      system: system,
      loopback: LoopbackOAuthConsentBrowser(),
    );
