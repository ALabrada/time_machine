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

  factory Area.fromJson(Map<String, dynamic> json) => Area(
    minLat: (json['minLat'] as num).toDouble(),
    minLng: (json['minLng'] as num).toDouble(),
    maxLat: (json['maxLat'] as num).toDouble(),
    maxLng: (json['maxLng'] as num).toDouble(),
    zoom: (json['zoom'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'minLat': minLat,
    'minLng': minLng,
    'maxLat': maxLat,
    'maxLng': maxLng,
    if (zoom != null) 'zoom': zoom,
  };
}