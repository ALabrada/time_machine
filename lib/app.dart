import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_machine/pages/home_page.dart';
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'generated/l10n.dart';

class TimeMachineApp extends StatelessWidget {
  const TimeMachineApp({
    super.key,
    this.userAgent,
  });

  final String? userAgent;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<RouteObserver>(
          create: (_) => RouteObserver<ModalRoute<void>>(),
        ),
        Provider<GoRouter>(
          create: (context) {
            return GoRouter(
              routes: [
                GoRoute(
                    path: '/',
                    builder: (context, state) => FixedOrientationView(
                      orientations: [DeviceOrientation.portraitUp],
                      child: HomePage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'camera',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: CameraPage(
                            pictureId: int.tryParse(state.uri.queryParameters['pictureId'] ?? ''),
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'import',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: ImportPage(
                            pictureId: int.tryParse(state.uri.queryParameters['pictureId'] ?? ''),
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'picture/:pictureId',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: PicturePage(
                            pictureId: int.tryParse(state.pathParameters['pictureId'] ?? ''),
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'gallery/:recordId',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: ComparisonPage(
                            recordId: int.tryParse(state.pathParameters['recordId'] ?? ''),
                          ),
                        ),
                        routes: [
                          GoRoute(
                            path: 'upload',
                            builder: (context, state) => FixedOrientationView(
                              orientations: DeviceOrientation.values,
                              child: UploadPage(
                                recordId: int.tryParse(state.pathParameters['recordId'] ?? ''),
                                webPage: state.uri.queryParameters['webPage'] ?? '',
                              ),
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'settings',
                        builder: (context, state) => FixedOrientationView(
                          orientations: [DeviceOrientation.portraitUp],
                          child: ConfigurationPage(),
                        ),
                      ),
                    ]
                ),
              ],
              observers: [
                context.read<RouteObserver>(),
              ],
            );
          },
        ),
        Provider<NetworkService>(
          create: (_) => NetworkService(
            userAgent: userAgent,
            providers: {
              'pastvu': PastVuProvider(
                userAgent: userAgent,
              ),
              'russiainphoto': RussiaInPhotoProvider(
                userAgent: userAgent,
              ),
            },
          ),
        ),
        FutureProvider<DatabaseService?>(
          initialData: null,
          create: (_) => DatabaseService.load(),
          lazy: false,
        ),
        FutureProvider<SharedPreferencesWithCache?>(
          initialData: null,
          create: (_) => SharedPreferencesWithCache.create(
            cacheOptions: SharedPreferencesWithCacheOptions(),
          ),
          lazy: false,
        ),
        Provider<ConfigurationService>(
          create: (context) => ConfigurationService(
            preferences: context.read,
          ),
        ),
      ],
      builder: (context, _) {
        return MaterialApp.router(
          title: context.read<PackageInfo?>()?.appName,
          localizationsDelegates: [
            S.delegate,
            CamLocalizations.delegate,
            ConfigLocalizations.delegate,
            ImgLocalizations.delegate,
            MapLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          theme: ThemeData.from(
            colorScheme: colorScheme,
            useMaterial3: true,
          ),
          routerConfig: context.read<GoRouter>(),
        );
      },
    );
  }
}