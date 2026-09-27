import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_map/domain/tile_offset.dart';
import 'package:time_machine_map/l10n/map_localizations.dart';

class AdaptiveTileLayer extends StatelessWidget {
  final MapTileServer tileServer;
  final TileOffset tileOffset;
  final String userAgent;

  const AdaptiveTileLayer({
    super.key,
    required this.tileServer,
    required this.tileOffset,
    this.userAgent = 'com.example.app',
  });

  @override
  Widget build(BuildContext context) {
    final url = tileServer.url(context);
    if (tileServer.format == TileFormat.image) {
      return TileLayer(
        urlTemplate: url,
        userAgentPackageName: userAgent,
        tileProvider: CancellableNetworkTileProvider(),
        subdomains: tileServer.subdomains ?? const ['a', 'b', 'c'],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          MapLocalizations.of(context).tileLoadError,
          textAlign: TextAlign.center,
          style: TextTheme.of(context).labelLarge,
        ),
      ),
    );
  }
}