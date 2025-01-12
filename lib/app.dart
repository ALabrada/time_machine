import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_machine/pages/home_page.dart';
import 'package:time_machine_cam/pages/camera_page.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';

class TimeMachineApp extends StatelessWidget {
  const TimeMachineApp({super.key});

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
                    builder: (context, state) => HomePage(),
                    routes: [
                      GoRoute(
                        path: 'camera',
                        builder: (context, state) => CameraPage(
                          pictureId: int.tryParse(state.uri.queryParameters['pictureId'] ?? ''),
                        ),
                      ),
                      GoRoute(
                        path: 'picture/:pictureId',
                        builder: (context, state) => PicturePage(
                          pictureId: int.tryParse(state.pathParameters['pictureId'] ?? ''),
                        ),
                      ),
                      GoRoute(
                        path: 'gallery/:recordId',
                        builder: (context, state) => ComparisonPage(
                          recordId: int.tryParse(state.pathParameters['recordId'] ?? ''),
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
            providers: {
              'pastvu': PastVuProvider(),
              'russiainphoto': RussiaInPhotoProvider(),
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
      ],
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Portable Time Machine',
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