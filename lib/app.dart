import 'package:cached_network_image/cached_network_image.dart';
import 'package:app_links/app_links.dart';
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
import 'package:time_machine/services/web_provider_auth.dart' as web_auth;
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/services/cloud_sync_service.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_img/services/proxy_telegram_service.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_map/services/vector_service.dart' as vs;
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
                        builder: (context, state) =>
                            (isTabletLayout(context) || kIsWeb)
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
        // Opens the OAuth authorize page in the system browser. Custom-scheme
        // providers return through the app's deep link; Google's desktop
        // client uses a loopback redirect instead.
        Provider<OAuthConsentBrowser>(
          create: (context) {
            final appLinks = context.read<AppLinks>();
            return createPlatformOAuthConsentBrowser(
              system: SystemBrowserOAuthConsentBrowser(
                redirectStream: () => _mergeDeepLinks(appLinks),
              ),
            );
          },
        ),
        Provider<CloudService>(
          create: (context) {
            final googleClientId = kIsWeb
                ? ''
                : switch (defaultTargetPlatform) {
                    TargetPlatform.iOS =>
                      secrets.GOOGLE_DRIVE_CLIENT_ID_IOS,
                    TargetPlatform.android =>
                      secrets.GOOGLE_DRIVE_CLIENT_ID_ANDROID,
                    _ => secrets.GOOGLE_DRIVE_CLIENT_ID_DESKTOP,
                  };
            final googleClientSecret =
                !kIsWeb &&
                    defaultTargetPlatform != TargetPlatform.iOS &&
                    defaultTargetPlatform != TargetPlatform.android &&
                    secrets.GOOGLE_DRIVE_CLIENT_SECRET_DESKTOP.isNotEmpty
                ? secrets.GOOGLE_DRIVE_CLIENT_SECRET_DESKTOP
                : null;
            final googleRedirectUri = !kIsWeb &&
                    defaultTargetPlatform != TargetPlatform.iOS &&
                    defaultTargetPlatform != TargetPlatform.android
                ? Uri.parse(secrets.GOOGLE_DRIVE_DESKTOP_REDIRECT_URI)
                : Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI);
            // OAuth providers keep their native implementation (system browser
            // + custom-scheme deep link) except on the web, where the proxy
            // backend mediates the flow and hosts the provider API calls.
            final backendUrl = Uri.tryParse(secrets.BACKEND_URL);
            final useBackendAuth =
                kIsWeb && backendUrl != null && backendUrl.hasAuthority;
            final configuredBackendProviders = secrets.BACKEND_PROVIDERS
                .split(',')
                .map((provider) => provider.trim())
                .where((provider) => provider.isNotEmpty)
                .toSet();
            bool providerEnabled(String provider) =>
                configuredBackendProviders.isEmpty ||
                configuredBackendProviders.contains(provider);
            final clouds = <String, CloudBase>{
              // Nextcloud needs no application credentials, so it is always
              // offered — including on web, where its login (server URL +
              // credentials) needs no OAuth/browser deep links.
              'nextcloud': NextCloudCloud(
                appRootFolderName: 'HistoryLens',
                tokenStore: SecureNextcloudTokenStore(),
              ),
              if (!kIsWeb &&
                  providerEnabled('gdrive') &&
                  googleClientId.isNotEmpty)
                'gdrive': GoogleDriveCloud(
                  // Mobile uses the custom-scheme deep link; the desktop OAuth
                  // client uses Google's loopback redirect.
                  appRootFolderName: 'HistoryLens',
                  signIn: GoogleDriveSignIn(
                    clientId: auth.ClientId(googleClientId, googleClientSecret),
                    redirectUri: googleRedirectUri,
                  ),
                  tokenStore: SecureGoogleDriveTokenStore(),
                ),
              if (!kIsWeb &&
                  providerEnabled('dropbox') &&
                  secrets.DROPBOX_APP_KEY.isNotEmpty)
                'dropbox': DropBoxCloud(
                  clientId: secrets.DROPBOX_APP_KEY,
                  redirectUri: secrets.DROPBOX_REDIRECT_URI,
                  tokenStore: SecureDropboxTokenStore(),
                ),
              if (!kIsWeb &&
                  providerEnabled('yandex') &&
                  secrets.YANDEX_CLIENT_ID.isNotEmpty)
                'yandex': YandexDiskCloud(
                  clientId: secrets.YANDEX_CLIENT_ID,
                  redirectUri: secrets.YANDEX_REDIRECT_URI,
                  tokenStore: SecureYandexDiskTokenStore(),
                ),
              if (useBackendAuth && providerEnabled('gdrive'))
                'gdrive': BackendProxyCloud(
                  providerId: 'gdrive',
                  backendUrl: backendUrl,
                  auth: web_auth.createWebProviderAuth(
                    providerId: 'gdrive',
                    backendUrl: backendUrl,
                  ),
                ),
              if (useBackendAuth && providerEnabled('dropbox'))
                'dropbox': BackendProxyCloud(
                  providerId: 'dropbox',
                  backendUrl: backendUrl,
                  auth: web_auth.createWebProviderAuth(
                    providerId: 'dropbox',
                    backendUrl: backendUrl,
                  ),
                ),
              if (useBackendAuth && providerEnabled('yandex'))
                'yandex': BackendProxyCloud(
                  providerId: 'yandex',
                  backendUrl: backendUrl,
                  auth: web_auth.createWebProviderAuth(
                    providerId: 'yandex',
                    backendUrl: backendUrl,
                  ),
                ),
            };
            return CloudService(clouds: clouds);
          },
        ),
        Provider<NetworkService>(
          create: (context) {
            final geocoders = {
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
            };
            final providers = {
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
            };
            // Outbound provider/geocoder requests cannot reach their servers
            // from the browser (CORS); route them through the proxy backend
            // when one is configured.
            if (kIsWeb && secrets.BACKEND_URL.isNotEmpty) {
              return ProxyNetworkService(
                backendUrl: secrets.BACKEND_URL,
                geocoders: geocoders,
                providers: providers,
                userAgent: userAgent,
              );
            }
            return NetworkService(
              userAgent: userAgent,
              geocoders: geocoders,
              providers: providers,
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
          create: (context) {
            final cacheManager = CachedNetworkImageProvider.defaultCacheManager;
            // On the web the browser cannot load provider images directly
            // (CORS); fetch them through the proxy backend instead.
            if (kIsWeb && secrets.BACKEND_URL.isNotEmpty) {
              return ProxyCacheService(
                backendUrl: secrets.BACKEND_URL,
                userAgent: userAgent,
                cacheManager: cacheManager,
              );
            }
            return CacheService(
              cacheManager: cacheManager,
              pathExpander: (path) {
                final databaseService = context.read<DatabaseService?>();
                return databaseService == null
                    ? path
                    : databaseService.expandPath(path);
              },
            );
          },
        ),
        Provider<SharingService>(
          create: (_) => SharingService(
            // OAuth consent returns arrive as custom-scheme deep links while
            // the app is running; do not treat them as file shares.
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
          create: (context) {
            // On the web the bot token must not be shipped with the app, so
            // publishing goes through the proxy backend when the build declares
            // that the backend supports Telegram.
            if (kIsWeb) {
              if (secrets.BACKEND_URL.isEmpty || !secrets.BACKEND_TELEGRAM) {
                return null;
              }
              return ProxyTelegramService(backendUrl: secrets.BACKEND_URL);
            }
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
              photoResolver: context.read<CacheService>(),
            );
          },
        ),
        Provider<vs.VectorService>(
          create: (_) => vs.VectorService(
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
String? oauthDeepLinkRedirect(Uri uri) {
  if (oauthRedirectSchemes().contains(uri.scheme)) {
    return '/';
  }
  return null;
}

/// Consumes the OAuth consent return *before* GoRouter sees it.
///
/// Flutter's Android embedding forwards the custom-scheme intent of a warm
/// OAuth return to every `WidgetsBindingObserver` via
/// `didPushRouteInformation` (in registration order, until one returns true).
/// Registering this first means GoRouter never tries to "navigate" to a
/// provider's redirect (e.g. `com.fakegem.historylens:/oauth2redirect-yandex?...`),
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