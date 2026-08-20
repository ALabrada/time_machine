import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:time_machine/app.dart';
import 'package:time_machine/secrets.dart' as secrets;

void main() {
  testWidgets('OAuth deep link bounces home instead of throwing', (tester) async {
    final redirectScheme = Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI).scheme;
    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) => oauthDeepLinkRedirect(
        state.uri,
        redirectScheme: redirectScheme,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(
        uri: Uri.parse(
          '${secrets.GOOGLE_DRIVE_REDIRECT_URI}?code=dummy&state=xyz',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('home'), findsOneWidget);
  });
}