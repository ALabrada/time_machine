import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:time_machine/app.dart';
import 'package:fk_user_agent/fk_user_agent.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  await initializeDateFormatting(null, null);
  if (kIsWeb) {
    runApp(TimeMachineApp());
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    await FkUserAgent.init();
    final userAgent = FkUserAgent.userAgent;
    final packageInfo = await PackageInfo.fromPlatform();
    runApp(TimeMachineApp(
      userAgent: "HistoryLens/${packageInfo.version} $userAgent",
      packageInfo: packageInfo,
    ));
  }
}
