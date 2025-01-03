class Area {
  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
  final double? zoom;

  const Area({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
    this.zoom,
  });
}