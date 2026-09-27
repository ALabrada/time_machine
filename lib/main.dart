import 'dart:io';

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
    await registerLinuxAuthSchemeHandler();
    // Swallows the warm OAuth consent return before GoRouter sees it, so the
    // page the user signed in from stays put; the auth flow reads the URI off
    // the app_links stream instead.
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

/// The custom URL scheme used by every OAuth provider consent return. Because
/// the headless Linux bundle ships no .desktop file, register one for the
/// current executable so the system routes `scheme://` redirects back here.
///
/// Writes `~/.local/share/applications/history_lens.desktop` and registers it
/// as the default handler for the scheme; tolerant of environments without
/// xdg tooling (the failure only disables OAuth return deep links).
Future<void> registerLinuxAuthSchemeHandler() async {
  if (defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  const scheme = 'com.fakegem.historylens';
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }
  final applicationsDir =
      Directory('$home/.local/share/applications');
  try {
    await applicationsDir.create(recursive: true);
    final desktopFile = File('${applicationsDir.path}/history_lens.desktop');
    final exec = Platform.resolvedExecutable;
    await desktopFile.writeAsString('''
[Desktop Entry]
Type=Application
Name=History Lens
TryExec=$exec
Exec=$exec %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/$scheme;
''');
    await _runQuiet([
      'update-desktop-database',
      applicationsDir.path,
    ]);
    await _runQuiet([
      'xdg-mime',
      'default',
      'history_lens.desktop',
      'x-scheme-handler/$scheme',
    ]);
  } catch (_) {
    // Registration is best-effort; the OAuth return just needs the scheme to
    // reach the running app through GApplication.
  }
}

Future<void> _runQuiet(List<String> command) async {
  try {
    await Process.run(command.first, command.sublist(1));
  } catch (_) {
    // Missing xdg tooling is fine; the desktop entry is still written.
  }
}
