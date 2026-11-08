import 'package:latlong2/latlong.dart';

import 'package:time_machine_core/domain/area.dart';
import 'package:time_machine_core/domain/location.dart';

const _userAgentHeader = 'user-agent';
const _acceptHeader = 'accept';

const String userAgentHeader = _userAgentHeader;
const String acceptHeader = _acceptHeader;

Area areaAround({required Location location, required double radius}) {
  final points = const Distance();
  final north = points.offset(LatLng(location.lat, location.lng), radius, 0);
  final east = points.offset(LatLng(location.lat, location.lng), radius, 90);
  final south = points.offset(LatLng(location.lat, location.lng), radius, 180);
  final west = points.offset(LatLng(location.lat, location.lng), radius, -90);
  assert(north.latitude >= south.latitude);
  assert(east.longitude >= west.longitude);
  return Area(
    minLat: south.latitude,
    minLng: west.longitude,
    maxLat: north.latitude,
    maxLng: east.longitude,
  );
}

bool isWithinRadius({
  required Location location,
  required double radius,
  required double latitude,
  required double longitude,
}) {
  final distance = const Distance();
  final meters = distance.as(
    LengthUnit.Meter,
    LatLng(location.lat, location.lng),
    LatLng(latitude, longitude),
  );
  return meters <= radius;
}