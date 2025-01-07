import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:time_machine/pages/home_page.dart';
import 'package:time_machine_cam/pages/camera_page.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_img/pages/picture_page.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';

final _router = GoRouter(
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
        ]
      ),
    ]
);

class TimeMachineApp extends StatelessWidget {
  const TimeMachineApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<NetworkService>(
          create: (_) => NetworkService(
            providers: {
              'pastvu': PastVuProvider(),
            },
          ),
        ),
        FutureProvider<DatabaseService?>(
          initialData: null,
          create: (_) => DatabaseService.load(),
          lazy: false,
        ),
      ],
      child: MaterialApp.router(
        title: 'Portable Time Machine',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // TRY THIS: Try running your application with "flutter run". You'll see
          // the application has a purple toolbar. Then, without quitting the app,
          // try changing the seedColor in the colorScheme below to Colors.green
          // and then invoke "hot reload" (save your changes or press the "hot
          // reload" button in a Flutter-supported IDE, or press "r" if you used
          // the command line to start the app).
          //
          // Notice that the counter didn't reset back to zero; the application
          // state is not lost during the reload. To reset the state, use hot
          // restart instead.
          //
          // This works for code too, not just values: Most code changes can be
          // tested with just a hot reload.
          colorScheme: colorScheme,
          useMaterial3: true,
        ),
        routerConfig: _router,
      ),
    );
  }
}