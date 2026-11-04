import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_map/l10n/map_localizations.dart';
import 'package:time_machine_map/domain/vector_tile_style.dart';
import 'package:time_machine_map/services/vector_service.dart';
import 'package:time_machine_res/molecules/loading_container.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'rendered_vector_tile_provider.dart';

class AdaptiveTileLayer extends StatelessWidget {
  final MapTileServer tileServer;
  final String userAgent;

  const AdaptiveTileLayer({
    super.key,
    required this.tileServer,
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
    final vectorService = context.read<VectorService>();
    return FutureBuilder<VectorTileStyle>(
      future: vectorService.loadStyle(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
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
        final style = snapshot.data;
        if (style == null) {
          return const SizedBox.shrink();
        }
        return _VectorTileLayer(
          serverId: url,
          style: style,
          vectorService: vectorService,
        );
      },
    );
  }
}

class _VectorTileLayer extends StatefulWidget {
  final String serverId;
  final VectorTileStyle style;
  final VectorService vectorService;

  const _VectorTileLayer({
    required this.serverId,
    required this.style,
    required this.vectorService,
  });

  @override
  State<_VectorTileLayer> createState() => _VectorTileLayerState();
}

class _VectorTileLayerState extends State<_VectorTileLayer> {
  late Future<_PreparedStyle> _preparedStyle;

  @override
  void initState() {
    super.initState();
    _preparedStyle = _prepare(widget.style);
  }

  @override
  void didUpdateWidget(covariant _VectorTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.style, widget.style)) {
      _preparedStyle = _prepare(widget.style);
    }
  }

  Future<_PreparedStyle> _prepare(VectorTileStyle style) async {
    final theme = style.readTheme();
    final sprites = style.sprites;
    if (sprites == null) {
      return _PreparedStyle(theme);
    }
    try {
      final spriteIndex = sprites.readContent();
      final spriteAtlas = await sprites.readImage();
      return _PreparedStyle(theme, spriteIndex: spriteIndex, spriteAtlas: spriteAtlas);
    } catch (e) {
      debugPrint('Error loading sprites: $e');
      return _PreparedStyle(theme);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PreparedStyle>(
      future: _preparedStyle,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        final prepared = snapshot.data;
        if (prepared == null) {
          return const SizedBox.shrink();
        }
        final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
        return TileLayer(
          tileProvider: RenderedVectorTileProvider(
            serverId: widget.serverId,
            style: widget.style,
            vectorService: widget.vectorService,
            theme: prepared.theme,
            spriteIndex: prepared.spriteIndex,
            spriteAtlas: prepared.spriteAtlas,
            scale: scale,
          ),
        );
      },
    );
  }
}

class _PreparedStyle {
  final vtr.Theme theme;
  final vtr.SpriteIndex? spriteIndex;
  final ui.Image? spriteAtlas;

  _PreparedStyle(this.theme, {this.spriteIndex, this.spriteAtlas});
}
