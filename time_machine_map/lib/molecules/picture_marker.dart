import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_db/time_machine_db.dart';

class PictureMarker extends Marker {
  PictureMarker({
    super.key,
    required this.picture,
    required super.child,
    super.width = 40,
    super.height = 40,
    super.alignment,
    super.rotate,
  }) : super(
    point: LatLng(picture.latitude, picture.longitude),
  );

  final Picture picture;
}