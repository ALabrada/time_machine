import 'package:time_machine_net/domain/location.dart';

class Picture {
  const Picture({
    this.id,
    required this.url,
    this.previewUrl,
    this.description,
    required this.location,
    this.altitude,
    this.bearing,
    this.time,
  });

  final String? id;
  final String url;
  final String? previewUrl;
  final String? description;
  final Location location;
  final double? altitude;
  final double? bearing;
  final String? time;
}