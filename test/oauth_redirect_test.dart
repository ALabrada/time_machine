import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:time_machine/app.dart';
import 'package:time_machine/secrets.dart' as secrets;

void main() {
  final redirectSchemes = {
    Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI).scheme,
    secrets.YANDEX_CUSTOM_URI_SCHEME,
  };

  Uri oauthUri(String scheme) =>
      Uri.parse('$scheme:/oauth2redirect?code=dummy&state=xyz');

  testWidgets('OAuth deep link bounces home instead of throwing',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) =>
          oauthDeepLinkRedirect(state.uri, redirectSchemes: redirectSchemes),
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

    for (final scheme in redirectSchemes) {
      router.routeInformationProvider.didPushRouteInformation(
        RouteInformation(uri: oauthUri(scheme)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('home'), findsOneWidget);
    }
  });

  group('OAuthDeepLinkObserver', () {
    test('consumes only the OAuth redirect schemes', () async {
      final observer = OAuthDeepLinkObserver({'com.fakegem.historylens'});

      expect(
        await observer.didPushRouteInformation(
          RouteInformation(
            uri: Uri.parse('com.fakegem.historylens:/oauth2redirect'),
          ),
        ),
        isTrue,
      );
      expect(
        await observer.didPushRouteInformation(
          RouteInformation(uri: Uri.parse('https://example.com/page')),
        ),
        isFalse,
      );
    });

    testWidgets('warm push is swallowed so the current page stays',
        (tester) async {
      final observer = OAuthDeepLinkObserver(oauthRedirectSchemes());
      WidgetsBinding.instance.addObserver(observer);
      addTearDown(() => WidgetsBinding.instance.removeObserver(observer));

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/cloud',
            builder: (context, state) => const Scaffold(body: Text('cloud')),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/cloud');
      await tester.pumpAndSettle();
      expect(find.text('cloud'), findsOneWidget);

      for (final scheme in redirectSchemes) {
        final handled = await WidgetsBinding.instance.handlePushRoute(
          oauthUri(scheme).toString(),
        );
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        expect(tester.takeException(), isNull);
        expect(router.routeInformationProvider.value.uri.path, '/cloud');
        expect(find.text('cloud'), findsOneWidget);
      }
    });
  });
}