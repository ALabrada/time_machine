/// Describes a tile size and zoom offset so that loaded tiles can be used to
/// render a larger or smaller area.
class TileOffset {
  /// [zoomOffset] the zoom offset, usually 0. A negative offset will cause tiles
  /// to be loaded at a lower zoom level than normal. E.g. a zoomOffset of -1 will
  /// cause the map to load tiles at zoom level 13 when the map is at zoom level 14.
  final int zoomOffset;

  const TileOffset({required this.zoomOffset});
}