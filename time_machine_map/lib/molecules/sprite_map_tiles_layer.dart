import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/src/loader/caching_tile_loader.dart';
import 'package:vector_map_tiles/src/model/tile_data_model.dart';
import 'package:vector_map_tiles/src/widgets/abstract_map_layer_state.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../services/vector_service.dart';
import 'sprite_tile_widget.dart';

class SpriteMapTilesLayer extends AbstractMapLayer {
  final String serverId;
  final SpriteIndex? spriteIndex;
  final ui.Image? spriteAtlas;
  final VectorService vectorService;

  const SpriteMapTilesLayer({
    super.key,
    required this.serverId,
    required super.mapProperties,
    this.spriteIndex,
    this.spriteAtlas,
    required this.vectorService,
  }) : super(tileLoaderFactory: createCachingTileLoader);

  @override
  State<StatefulWidget> createState() => SpriteMapTilesLayerState();
}

class SpriteMapTilesLayerState
    extends AbstractMapLayerState<SpriteMapTilesLayer> {
  List<String> _previousTileKeys = [];

  @override
  Widget build(BuildContext context) {
    updateTiles(context);
    final displayReadyModels =
        mapTiles.tileModels.where((m) => m.isDisplayReady).toList();

    final currentTileKeys =
        displayReadyModels.map((it) => it.tile.key()).toList();
    if (!_tilesEqual(currentTileKeys, _previousTileKeys)) {
      _previousTileKeys = currentTileKeys;
      onTilesChanged();
    }

    final camera = MapCamera.maybeOf(context);
    final correction = camera != null
        ? Offset(
            (camera.size.width - camera.nonRotatedSize.width) / 2,
            (camera.size.height - camera.nonRotatedSize.height) / 2,
          )
        : Offset.zero;

    return Stack(
      children:
          displayReadyModels.map((m) => _toTile(m, correction)).toList(),
    );
  }

  bool _tilesEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setA = a.toSet();
    final setB = b.toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }

  Widget _toTile(TileDataModel model, Offset correction) {
    final tilePosition = model.tilePosition;
    return Positioned(
      key: ValueKey(model.tile.key()),
      left: tilePosition.position.topLeft.dx + correction.dx,
      top: tilePosition.position.topLeft.dy + correction.dy,
      width: tilePosition.position.size.width,
      height: tilePosition.position.size.height,
      child: SpriteTileWidget(
        serverId: widget.serverId,
        mapProperties: widget.mapProperties,
        model: model,
        vectorService: widget.vectorService,
        spriteIndex: widget.spriteIndex,
        spriteAtlas: widget.spriteAtlas,
        scale: MediaQuery.of(context).devicePixelRatio,
      ),
    );
  }
}
