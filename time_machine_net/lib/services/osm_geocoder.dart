import 'package:intl/intl.dart';
import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:time_machine_db/domain/location.dart';
import 'package:time_machine_net/domain/place_info.dart';

import 'network_service.dart';

class OsmSearchEngine implements GeocodingService {
  @override
  Future<List<PlaceInfo>> searchAddress(String query) async {
    final result = await Nominatim.searchByName(
      query: query,
      language: Intl.defaultLocale,
    );
    return List.generate(result.length, (idx) {
      final model = result[idx];
      return PlaceInfo(
        name: model.displayName,
        lat: model.lat,
        lng: model.lon,
      );
    });
  }

  @override
  Future<List<PlaceInfo>> searchCoordinates(Location location) async {
    final result = await Nominatim.reverseSearch(
      lat: location.lat,
      lon: location.lng,
      language: Intl.defaultLocale,
    );
    return [
      PlaceInfo(
        name: result.displayName,
        lat: result.lat,
        lng: result.lon,
      ),
    ];
  }
}