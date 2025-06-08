import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:time_machine/app.dart';
import 'package:fk_user_agent/fk_user_agent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FkUserAgent.init();
  final userAgent = FkUserAgent.userAgent;
  final packageInfo = await PackageInfo.fromPlatform();
  runApp(TimeMachineApp(
    userAgent: "HistoryLens/${packageInfo.version} $userAgent",
  ));
}
