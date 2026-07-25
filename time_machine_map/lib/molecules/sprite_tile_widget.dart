import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_map_tiles/src/model/map_properties.dart';
import 'package:vector_map_tiles/src/model/tile_data_model.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../services/vector_service.dart';

class SpriteTileWidget extends StatefulWidget {
  final String serverId;
  final TileDataModel model;
  final MapProperties mapProperties;
  final VectorService vectorService;
  final SpriteIndex? spriteIndex;
  final ui.Image? spriteAtlas;
  final double scale;

  SpriteTileWidget({
    required this.serverId,
    required this.model,
    required this.mapProperties,
    required this.vectorService,
    this.spriteIndex,
    this.spriteAtlas,
    this.scale = 1.0,
  }) : super(key: Key('tile_${model.tile.key()}'));

  @override
  State<StatefulWidget> createState() => SpriteTileWidgetState();
}

class SpriteTileWidgetState extends State<SpriteTileWidget> {
  ui.Image? _displayImage;
  String? _currentTileKey;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _currentTileKey = widget.model.tile.key();
    _loadTile();
  }

  @override
  void didUpdateWidget(covariant SpriteTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = widget.model.tile.key();
    if (_currentTileKey != newKey ||
        oldWidget.model.tileset != widget.model.tileset) {
      _currentTileKey = newKey;
      _loadTile();
    }
  }

  Future<void> _loadTile() async {
    final model = widget.model;
    if (model.tileset == null) return;

    final generation = ++_generation;

    try {
      final image = await widget.vectorService.renderTileImage(
        serverId: widget.serverId,
        z: model.tile.z,
        x: model.tile.x,
        y: model.tile.y,
        theme: widget.mapProperties.theme,
        tileset: model.tileset!,
        rasterTileset:
            model.rasterTileset ?? const RasterTileset(tiles: {}),
        spriteIndex: widget.spriteIndex,
        spriteAtlas: widget.spriteAtlas,
        scale: widget.scale,
      );

      if (!mounted || generation != _generation) return;
      setState(() => _displayImage = image);
    } catch (e) {
      if (mounted && generation == _generation) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayImage != null) {
      return RawImage(
        image: _displayImage!,
        width: widget.model.tilePosition.position.size.width,
        height: widget.model.tilePosition.position.size.height,
        fit: BoxFit.fill,
      );
    }
    return const SizedBox.shrink();
  }
}
