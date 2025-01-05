import 'package:ar_location_view/ar_location_view.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';

class PictureAnnotation extends ArAnnotation  {
  PictureAnnotation({
    required super.uid,
    required this.picture,
    this.provider,
  }) : super(position: _getPosition(picture));

  final String? provider;
  final Picture picture;

  static Position _getPosition(Picture model) {
    return Position(
      longitude: model.location.lng,
      latitude: model.location.lat,
      timestamp: DateTime.timestamp(),
      accuracy: 0,
      altitude: model.altitude ?? 0,
      altitudeAccuracy: 0,
      heading: model.bearing ?? 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}