import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:vector_math/vector_math_64.dart';

class TransformationService {
  const TransformationService({
    required this.origin,
    this.maxDistance=10000000,
  });

  final Location origin;
  final double maxDistance;

  Vector3? transformOrientation(double? bearing) {
    if (bearing == null) {
      return null;
    }
    final y = 0.0;
    final x = cos(pi * bearing / 180);
    final z = -1 * sin(pi * bearing / 180);
    final v = Vector3(x, y, z);
    v.normalize();
    return v;
  }

  Vector3 transformPosition(Location location) {
    final degree = (360 + Geolocator.bearingBetween(origin.lat, origin.lng, location.lat, location.lng)) % 360;
    final distance = Geolocator.distanceBetween(origin.lat, origin.lng, location.lat, location.lng);
    final y = 0.0;
    final x = distance * cos(pi * degree / 180);
    final z = -1 * distance * sin(pi * degree / 180);
    return Vector3(x, y, z);
  }

  Vector3 transformScale(Location location) {
    final distance = Geolocator.distanceBetween(origin.lat, origin.lng, location.lat, location.lng);
    final scale = max(0, maxDistance - distance) / maxDistance;
    return Vector3(scale, scale, scale);
  }
}