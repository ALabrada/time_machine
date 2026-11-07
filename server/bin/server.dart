import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:time_machine_cloud/services/image_cache.dart';
import 'package:time_machine_server/handler.dart';
import 'package:time_machine_server/network.dart';
import 'package:time_machine_server/rate_limit.dart';
import 'package:time_machine_server/server_config.dart';

Future<void> main() async {
  final config = ServerConfig.load();
  String? optional(String key) {
    final value = config[key];
    return value.isEmpty ? null : value;
  }

  final address =
      InternetAddress.tryParse(config['HOST']) ?? InternetAddress.anyIPv4;
  final port = int.tryParse(config['PORT']) ?? 8080;
  final userAgent = config['PROXY_USER_AGENT'].isEmpty
      ? 'history-lens-proxy/1.0'
      : config['PROXY_USER_AGENT'];

  final allowedImageHosts = {
    ...defaultAllowedImageHosts,
    ...(config['ALLOWED_IMAGE_HOSTS'])
        .split(',')
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty),
  };

  final diskDir = optional('IMAGE_CACHE_DIR');
  final imageFetcher = CachedImageFetcher(
    diskDir: diskDir == null ? null : Directory(diskDir),
    memoryLimit:
        int.tryParse(config['IMAGE_CACHE_MEMORY'])?.clamp(0, 1 << 30) ?? 5000,
    maxDiskSizeBytes:
        int.tryParse(config['IMAGE_CACHE_MAX_BYTES'])?.clamp(0, 1 << 62) ??
            (512 * 1024 * 1024),
    allowedHosts: allowedImageHosts.toList(),
  );

  final limit =
      int.tryParse(config['RATE_LIMIT_PER_MINUTE'])?.clamp(1, 1 << 30) ?? 120;

  final networkService = buildNetworkService(
    userAgent: userAgent,
    vkMapsApiKey: optional('VK_MAPS_API_KEY'),
    yandexApiKey: optional('YANDEX_API_KEY'),
    geonamesUserName: optional('GEONAMES_USERNAME'),
  );

  final webBuildDirValue = optional('WEB_BUILD_DIR');
  Directory? webBuildDir;
  if (webBuildDirValue != null) {
    // Accept both "build/web" (repository root) and "../build/web" (server
    // package) without requiring a particular working directory.
    final candidates = [
      webBuildDirValue,
      if (!webBuildDirValue.startsWith('/')) '../$webBuildDirValue',
    ];
    final resolved = candidates.firstWhere(
      (candidate) => Directory(candidate).existsSync(),
      orElse: () => '',
    );
    if (resolved.isEmpty) {
      throw StateError('WEB_BUILD_DIR "$webBuildDirValue" does not exist');
    }
    webBuildDir = Directory(resolved);
  }

  final handler = createHandler(
    networkService: networkService,
    imageFetcher: imageFetcher,
    rateLimiter: RateLimiter(maxRequestsPerWindow: limit),
    webBuildDir: webBuildDir,
    config: config,
  );

  final server = await shelf_io.serve(handler, address, port);
  print(
    'History Lens proxy listening on '
    'http://${server.address.address}:${server.port}',
  );
  print('image hosts allowed: ${allowedImageHosts.join(', ')}');
  print('rate limit: $limit req/min');
  if (webBuildDir != null) {
    print('serving web app from: $webBuildDir');
  }
}
