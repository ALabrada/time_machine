import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statusbarz/statusbarz.dart';
import 'package:time_machine/pages/home_page.dart';
import 'package:time_machine/secrets.dart' as secrets;
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/services/cloud_sync_service.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_img/services/telegram_service.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'l10n/app_localizations.dart';

class TimeMachineApp extends StatelessWidget {
  const TimeMachineApp({
    super.key,
    this.packageInfo,
    this.userAgent,
  });

  final PackageInfo? packageInfo;
  final String? userAgent;

  ThemeData _buildTheme(ColorScheme scheme) => ThemeData.from(
    colorScheme: scheme,
    useMaterial3: true,
  ).copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        statusBarColor: scheme.secondary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.secondary,
      actionBackgroundColor: scheme.primary,
      contentTextStyle: TextStyle(
        color: scheme.onSecondary,
      ),
    ),
  );

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
              // Do not adopt the engine's `defaultRouteName` (which on a cold
              // launch via the OAuth scheme is the deep link itself): start at
              // home and let the auth flow read the link off app_links.
              initialLocation: '/',
              redirect: (context, state) => oauthDeepLinkRedirect(state.uri),
              routes: [
                GoRoute(
                    path: '/',
                    builder: (context, state) => FixedOrientationView(
                      orientations: isTabletLayout(context)
                          ? DeviceOrientation.values
                          : [DeviceOrientation.portraitUp],
                      child: HomePage(
                        initialTab: state.uri.queryParameters['tab'],
                        pictureId: int.tryParse(state.uri.queryParameters['pictureId'] ?? ''),
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'camera',
                        builder: (context, state) => isTabletLayout(context)
                            ? FixedOrientationView(
                                orientations: DeviceOrientation.values,
                                child: TabletCameraPage(
                                  pictureId: int.tryParse(state.uri.queryParameters['pictureId'] ?? ''),
                                ),
                              )
                            : FixedOrientationView(
                                orientations: [DeviceOrientation.portraitUp],
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
                          child: LoadingContainer(
                            child: ComparisonPage(
                              recordId: int.tryParse(state.pathParameters['recordId'] ?? ''),
                            ),
                          ),
                        ),
                        routes: [
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
                            path: 'timelapse',
                            builder: (context, state) => FixedOrientationView(
                              orientations: DeviceOrientation.values,
                              child: TimelapsePage(
                                recordId: int.tryParse(state.pathParameters['recordId'] ?? ''),
                              ),
                            ),
                          ),
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
                        path: 'help',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: HelpPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'cloud',
                        builder: (context, state) => FixedOrientationView(
                          orientations: DeviceOrientation.values,
                          child: CloudPage(),
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
        Provider<AppLinks>(
          create: (_) => AppLinks(),
        ),
        Provider<GoogleDriveSignIn?>(
          create: (context) {
            final clientId =
                defaultTargetPlatform == TargetPlatform.iOS
                    ? secrets.GOOGLE_DRIVE_CLIENT_ID_IOS
                    : secrets.GOOGLE_DRIVE_CLIENT_ID_ANDROID;
            if (clientId.isEmpty) {
              // Google Drive is an opt-in cloud provider: without an OAuth
              // client id the consent flow cannot run, so do not register it.
              return null;
            }
            final appLinks = context.read<AppLinks>();
            return GoogleDriveSignIn(
              clientId: auth.ClientId(clientId, null),
              // Cold-start deep links (the app relaunched by the OAuth
              // scheme) are only reported by `getInitialUri`; warm redirects
              // arrive through `uriLinkStream`. Merge both into one stream.
              redirectStream: _mergeDeepLinks(appLinks),
              redirectUri: Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI),
            );
          },
        ),
        Provider<NetworkService>(
          create: (context) {
            final gdriveSignIn = context.read<GoogleDriveSignIn?>();
            final appLinks = context.read<AppLinks>();
            return NetworkService(
              clouds: {
                // Nextcloud needs no application credentials, so it is
                // always offered. OAuth-based providers are only registered
                // when their client credentials were configured at build
                // time; the Cloud page lists exactly the available ones.
                'nextcloud': NextCloudCloud(
                  appRootFolderName: 'HistoryLens',
                ),
                if (gdriveSignIn != null)
                  'gdrive': GoogleDriveCloud(
                    // No Google Play Services involved: OAuth runs through
                    // the system browser and a custom URL scheme delivered to
                    // the app as a deep link, so the cloud only needs the
                    // token store.
                    appRootFolderName: 'HistoryLens',
                    signIn: gdriveSignIn,
                  ),
                if (secrets.DROPBOX_APP_KEY.isNotEmpty)
                  'dropbox': DropBoxCloud(
                    clientId: secrets.DROPBOX_APP_KEY,
                    redirectUri: secrets.DROPBOX_REDIRECT_URI,
                  ),
                if (secrets.YANDEX_CLIENT_ID.isNotEmpty)
                  'yandex': YandexDiskCloud(
                    clientId: secrets.YANDEX_CLIENT_ID,
                    redirectUri: secrets.YANDEX_REDIRECT_URI,
                    // Consent returns through the same deep-link pipeline as
                    // Google: open the authorize URL in the system browser
                    // and receive the redirect on app_links.
                    redirectStream: _mergeDeepLinks(appLinks),
                  ),
              },
              userAgent: userAgent,
              geocoders: {
                if (userAgent != null)
                  'OSM': OsmSearchEngine(
                    userAgent: userAgent!,
                  ),
                if (secrets.VK_MAPS_API_KEY.isNotEmpty)
                  'VKMaps': VKMapsGeocoder(
                    userAgent: userAgent,
                    apiKey: secrets.VK_MAPS_API_KEY,
                  ),
                'Geonames': GeonamesGeocoder(
                  userAgent: userAgent,
                  userName: 'historylens',
                ),
              },
              providers: {
                'pastvu': PastVuProvider(
                  userAgent: userAgent,
                ),
                'russiainphoto': RussiaInPhotoProvider(
                  userAgent: userAgent,
                ),
                're.photos': RetroPhotosProvider(
                  userAgent: userAgent,
                ),
                'historypin': HistoryPinProvider(
                  userAgent: userAgent,
                ),
                'sepiatown': SepiaTownProvider(
                  userAgent: userAgent,
                ),
              },
            );
          },
        ),
        if (packageInfo != null)
          Provider.value(value: packageInfo!),
        FutureProvider<DatabaseService?>(
          initialData: null,
          create: (_) => DatabaseService.load(),
          lazy: false,
        ),
        Provider<CloudSyncService>(
          create: (_) => CloudSyncService(),
        ),
        Provider<UserMessageService>(
          create: (_) => UserMessageService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<CacheService>(
          create: (context) => CacheService(
            cacheManager: CachedNetworkImageProvider.defaultCacheManager,
            databaseService: () => context.read(),
          ),
        ),
        Provider<SharingService>(
          create: (_) => SharingService(
            // The OAuth consent return arrives on Android as an ACTION_VIEW
            // intent that the sharing plugin also sees; do not try to import
            // the `...:/oauth2redirect` URL as a shared file.
            ignoreUriSchemes: oauthRedirectSchemes(),
          ),
        ),
        FutureProvider<SharedPreferencesWithCache?>(
          initialData: null,
          create: (_) => SharedPreferencesWithCache.create(
            cacheOptions: SharedPreferencesWithCacheOptions(),
          ),
          lazy: false,
        ),
        ChangeNotifierProvider<ConfigurationService>(
          create: (context) => ConfigurationService(
            preferences: context.read,
          ),
        ),
        Provider<PhysicalButtonService>(
          create: (context) => PhysicalButtonService(
            configurationService: context.read(),
          ),
        ),
        Provider<TelegramService?>(
          create: (_) {
            final apiKey = secrets.telegramBotToken;
            final channelId = secrets.telegramChannelId;
            if (apiKey == null || channelId == null) {
              // No Telegram bot configured at build time: the share-to-
              // Telegram option is hidden from the sharing menu.
              return null;
            }
            return TelegramService(
              apiKey: apiKey,
              channelId: channelId,
              channelName: 'history_lens_app',
            );
          },
        ),
        Provider<VectorService>(
          create: (_) => VectorService(
            userAgent: userAgent,
            vkApiKey: secrets.VK_MAPS_API_KEY,
          ),
        ),
      ],
      builder: (context, _) {
        return MaterialApp.router(
          title: context.read<PackageInfo?>()?.appName,
          builder: (context, child) =>
              UserMessageListener(child: child ?? const SizedBox.shrink()),
          localizationsDelegates: [
            AppLocalizations.delegate,
            CamLocalizations.delegate,
            ConfigLocalizations.delegate,
            ImgLocalizations.delegate,
            MapLocalizations.delegate,
            ResLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _buildTheme(colorScheme),
          darkTheme: _buildTheme(darkColorScheme),
          themeMode: themeModeOf(
            context.watch<ConfigurationService>().themeMode ?? 'system',
          ),
          routerConfig: context.read<GoRouter>(),
        );
      },
    );
  }
}

/// Merges the cold-start deep link (relaunch via the OAuth URL scheme) with
/// the stream of warm deep links, so a consent redirect is never missed
/// regardless of whether the app was already running.
Stream<Uri> _mergeDeepLinks(AppLinks appLinks) async* {
  final initial = await appLinks.getInitialLink();
  if (initial != null) {
    yield initial;
  }
  yield* appLinks.uriLinkStream;
}

/// The custom URL scheme the OAuth consent return is delivered through. Every
/// provider (Google, Dropbox, Yandex) shares the `com.fakegem.historylens`
/// scheme and stays unambiguous by redirect path.
Set<String> oauthRedirectSchemes() => {
  Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI).scheme,
  Uri.parse(secrets.YANDEX_REDIRECT_URI).scheme,
};

/// Bounces custom-scheme deep links (the OAuth consent return) back to the
/// home route. The auth flow reads the URI off the app_links stream, so the
/// router must not try to match it or it throws "no routes for location".
///
/// This is a cold-start safety net: [OAuthDeepLinkObserver] swallows warm
/// redirects before they reach GoRouter, and GoRouter starts on '/', so only
/// an unexpected platform push ever gets here.
String? oauthDeepLinkRedirect(
  Uri uri, {
  Set<String>? redirectSchemes,
}) {
  if ((redirectSchemes ?? oauthRedirectSchemes()).contains(uri.scheme)) {
    return '/';
  }
  return null;
}

/// Consumes the OAuth consent return *before* GoRouter sees it.
///
/// Flutter's Android embedding forwards the custom-scheme intent of a warm
/// OAuth return to every `WidgetsBindingObserver` via
/// `didPushRouteInformation` (in registration order, until one returns true).
/// Registering this first means GoRouter never tries to "navigate" to
  /// a provider's redirect (e.g. `com.fakegem.historylens:/oauth2redirect-yandex?...`),
  /// so the page the user initiated the sign-in from (e.g. the Cloud page)
  /// stays put — the URI is consumed by the app_links stream instead.
class OAuthDeepLinkObserver extends WidgetsBindingObserver {
  OAuthDeepLinkObserver(this.redirectSchemes);

  final Set<String> redirectSchemes;

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    if (redirectSchemes.contains(routeInformation.uri.scheme)) {
      return SynchronousFuture(true);
    }
    return SynchronousFuture(false);
  }
}