class PlaceInfo {
  const PlaceInfo({
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String name;
  final double lat;
  final double lng;

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
  };
}