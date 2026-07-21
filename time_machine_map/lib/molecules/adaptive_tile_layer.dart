import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_map/services/vector_service.dart';
import 'package:time_machine_res/molecules/loading_container.dart';
import 'package:vector_map_tiles/src/cache/cache.dart';
import 'package:vector_map_tiles/src/model/map_properties.dart';
import 'package:vector_map_tiles/src/widgets/map_tiles_layer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

class AdaptiveTileLayer extends StatelessWidget {
  final MapTileServer tileServer;
  final TileOffset tileOffset;
  final int concurrency;
  final Duration fileCacheTtl;
  final int fileCacheMaximumSizeInBytes;
  final Future<Directory> Function()? cacheFolder;
  final String userAgent;

  const AdaptiveTileLayer({
    super.key,
    required this.tileServer,
    required this.tileOffset,
    this.concurrency = 4,
    this.fileCacheTtl = const Duration(days: 30),
    this.fileCacheMaximumSizeInBytes = 50 * 1024 * 1024,
    this.cacheFolder,
    this.userAgent = 'com.example.app',
  });

  @override
  Widget build(BuildContext context) {
    if (tileServer.format == TileFormat.image) {
      return TileLayer(
        urlTemplate: tileServer.url,
        userAgentPackageName: userAgent,
        tileProvider: CancellableNetworkTileProvider(),
        subdomains: tileServer.subdomains ?? const ['a', 'b', 'c'],
      );
    }
    return FutureBuilder(
      future: context.read<VectorService>().loadStyle(tileServer.url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        final style = snapshot.data;
        if (style == null) {
          return const SizedBox.shrink();
        }
        return SizedBox.expand(
          child: MapTilesLayer(
            mapProperties: MapProperties(
              tileProviders: style.providers,
              theme: style.theme,
              tileOffset: tileOffset,
              concurrency: concurrency,
              cacheProperties: CacheProperties(
                fileCacheTtl: fileCacheTtl,
                fileCacheMaximumSizeInBytes: fileCacheMaximumSizeInBytes,
                cacheFolder: cacheFolder,
              ),
            ),
          ),
        );
      },
    );
  }
}
