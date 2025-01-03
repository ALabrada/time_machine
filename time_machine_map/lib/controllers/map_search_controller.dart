import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_map/domain/place_info.dart';

class MapSearchController {
  final results = BehaviorSubject<List<PlaceInfo>>();

  Future<List<PlaceInfo>> locate(String name) async {
    final result = await Nominatim.searchByName(
      query: name,
    );
    final data = List.generate(result.length, (idx) {
      final model = result[idx];
      return PlaceInfo(
        name: model.displayName,
        lat: model.lat,
        lng: model.lon,
      );
    });
    results.value = data;
    return data;
  }
}