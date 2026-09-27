import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:time_machine_cloud/services/image_cache.dart';
import 'package:time_machine_server/handler.dart';
import 'package:time_machine_server/network.dart';
import 'package:time_machine_server/rate_limit.dart';

Future<void> main() async {
  final address = InternetAddress.tryParse(Platform.environment['HOST'] ?? '') ??
      InternetAddress.anyIPv4;
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final userAgent = Platform.environment['PROXY_USER_AGENT'] ?? 'history-lens-proxy/1.0';

  final allowedImageHosts = {
    ...defaultAllowedImageHosts,
    ...(Platform.environment['ALLOWED_IMAGE_HOSTS'] ?? '')
        .split(',')
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty),
  };

  final diskDir = Platform.environment['IMAGE_CACHE_DIR'];
  final imageFetcher = CachedImageFetcher(
    diskDir: diskDir == null ? null : Directory(diskDir),
    memoryLimit: int.tryParse(Platform.environment['IMAGE_CACHE_MEMORY'] ?? '')
            ?.clamp(0, 1 << 30) ??
        5000,
    maxDiskSizeBytes:
        int.tryParse(Platform.environment['IMAGE_CACHE_MAX_BYTES'] ?? '')
                ?.clamp(0, 1 << 62) ??
            (512 * 1024 * 1024),
    allowedHosts: allowedImageHosts.toList(),
  );

  final limit = int.tryParse(Platform.environment['RATE_LIMIT_PER_MINUTE'] ?? '')
          ?.clamp(1, 1 << 30) ??
      120;

  final networkService = buildNetworkService(
    userAgent: userAgent,
    vkMapsApiKey: Platform.environment['VK_MAPS_API_KEY'],
    yandexApiKey: Platform.environment['YANDEX_API_KEY'],
    geonamesUserName: Platform.environment['GEONAMES_USERNAME'],
  );

  final webBuildDir = Platform.environment['WEB_BUILD_DIR'];
  if (webBuildDir != null && !Directory(webBuildDir).existsSync()) {
    throw StateError('WEB_BUILD_DIR "$webBuildDir" does not exist');
  }

  final handler = createHandler(
    networkService: networkService,
    imageFetcher: imageFetcher,
    rateLimiter: RateLimiter(maxRequestsPerWindow: limit),
    webBuildDir: webBuildDir == null ? null : Directory(webBuildDir),
  );

  final server = await shelf_io.serve(handler, address, port);
  print('History Lens proxy listening on http://${server.address.address}:${server.port}');
  print('image hosts allowed: ${allowedImageHosts.join(', ')}');
  print('rate limit: $limit req/min');
  if (webBuildDir != null) {
    print('serving web app from: $webBuildDir');
  }
}