import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:time_machine/app.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:fk_user_agent/fk_user_agent.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  await initializeDateFormatting(null, null);
  if (kIsWeb) {
    runApp(TimeMachineApp());
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    // Swallows the warm OAuth consent return before GoRouter sees it, so the
    // page the sign-in started from (e.g. the Cloud page) is not navigated
    // away from. Must be registered before the router builds to run first.
    WidgetsBinding.instance.addObserver(
      OAuthDeepLinkObserver(oauthRedirectSchemes()),
    );
    await prefetchOsTabletStatus();
    final packageInfo = await PackageInfo.fromPlatform();
    // fk_user_agent reads a real device/WebView user agent on Android/iOS and
    // generates one from the operating system on desktop, so the same path
    // works for every native target.
    var userAgent =
        "HistoryLens/${packageInfo.version} ${defaultTargetPlatform.name}";
    try {
      await FkUserAgent.init();
      userAgent = "HistoryLens/${packageInfo.version} "
          "${FkUserAgent.userAgent ?? defaultTargetPlatform.name}";
    } on MissingPluginException {
      userAgent =
          "HistoryLens/${packageInfo.version} ${defaultTargetPlatform.name}";
    }
    runApp(TimeMachineApp(
      userAgent: userAgent,
      packageInfo: packageInfo,
    ));
  }
}
