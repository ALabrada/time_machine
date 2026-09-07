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
    final gdriveScheme = Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI).scheme;
    return MultiProvider(
      providers: [
        Provider<RouteObserver>(
          create: (_) => RouteObserver<ModalRoute<void>>(),
        ),
        Provider<GoRouter>(
          create: (context) {
            return GoRouter(
              redirect: (context, state) => oauthDeepLinkRedirect(
                state.uri,
                redirectScheme: gdriveScheme,
              ),
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
        Provider<NetworkService>(
          create: (_) => NetworkService(
            clouds: {
              'supabase': SupabaseCloud(
                supabaseUrl: secrets.SUPABASE_URL,
                supabaseKey: secrets.SUPABASE_ANON_KEY,
              ),
              // No Google Play Services involved: OAuth runs through the
              // system browser and a custom URL scheme delivered to the app
              // as a deep link, so the cloud only needs the token store.
              'gdrive': GoogleDriveCloud(),
              'dropbox': DropBoxCloud(
                clientId: secrets.DROPBOX_APP_KEY,
                redirectUri: secrets.DROPBOX_REDIRECT_URI,
              ),
            },
            userAgent: userAgent,
            geocoders: {
              if (userAgent != null)
                'OSM': OsmSearchEngine(
                  userAgent: userAgent!,
                ),
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
          ),
        ),
        Provider<GoogleDriveSignIn>(
          create: (_) {
            final appLinks = AppLinks();
            return GoogleDriveSignIn(
              clientId: auth.ClientId(
                defaultTargetPlatform == TargetPlatform.iOS
                    ? secrets.GOOGLE_DRIVE_CLIENT_ID_IOS
                    : secrets.GOOGLE_DRIVE_CLIENT_ID_ANDROID,
                null,
              ),
              // Cold-start deep links (the app relaunched by the OAuth
              // scheme) are only reported by `getInitialUri`; warm redirects
              // arrive through `uriLinkStream`. Merge both into one stream.
              redirectStream: _mergeDeepLinks(appLinks),
              redirectUri: Uri.parse(secrets.GOOGLE_DRIVE_REDIRECT_URI),
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
          create: (context) => CloudSyncService(
            databaseService: context.read(),
          ),
        ),
        Provider<CacheService>(
          create: (context) => CacheService(
            cacheManager: CachedNetworkImageProvider.defaultCacheManager,
            databaseService: () => context.read(),
          ),
        ),
        Provider<SharingService>(
          create: (_) => SharingService(
            ignoreUriSchemes: {gdriveScheme},
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
        Provider<TelegramService>(
          create: (_) => TelegramService(
            apiKey: secrets.TELEGRAM_BOT_TOKEN,
            channelId: secrets.TELEGRAM_CHANNEL_ID,
            channelName: 'history_lens_app',
          ),
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

/// Bounces custom-scheme deep links (the OAuth consent return) back to the
/// home route. The auth flow reads the URI off the app_links stream, so the
/// router must not try to match it or it throws "no routes for location".
String? oauthDeepLinkRedirect(Uri uri, {required String redirectScheme}) {
  if (uri.scheme == redirectScheme) {
    return '/';
  }
  return null;
}