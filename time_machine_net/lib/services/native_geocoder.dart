import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:time_machine_db/domain/location.dart' as db;
import 'package:time_machine_net/domain/place_info.dart';

import 'network_service.dart';

class NativeGeocoder implements GeocodingService {
  @override
  Future<List<PlaceInfo>> searchAddress(String query) async {
    final locale = Intl.defaultLocale;
    if (locale != null) {
      await setLocaleIdentifier(locale);
    }
    final result = await locationFromAddress(query);
    return List.generate(result.length, (idx) {
      final model = result[idx];
      return PlaceInfo(
        name: query,
        lat: model.latitude,
        lng: model.longitude,
      );
    });
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates(db.Location location) async {
    final locale = Intl.defaultLocale;
    if (locale != null) {
      await setLocaleIdentifier(locale);
    }
    final result = await placemarkFromCoordinates(
      location.lat,
      location.lng
    );
    return List.generate(result.length, (idx) {
      final model = result[idx];
      return PlaceInfo(
        name: model.name ?? '',
        lat: location.lat,
        lng: location.lng,
      );
    });
  }
}