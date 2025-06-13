import 'package:rxdart/rxdart.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_net/domain/place_info.dart';
import 'package:time_machine_net/services/network_service.dart';

class MapSearchController {
  MapSearchController({
    this.configurationService,
    this.networkService,
  });

  final ConfigurationService? configurationService;
  final NetworkService? networkService;
  final results = BehaviorSubject<List<PlaceInfo>>();

  Future<List<PlaceInfo>> locate(String name) async {
    final source = configurationService?.geocoder ?? ConfigurationService.defaultGeocoder;
    final result = await networkService?.searchAddress(query: name, source: source) ?? <PlaceInfo>[];
    final data = List.generate(result.length, (idx) {
      final model = result[idx];
      return PlaceInfo(
        name: model.name,
        lat: model.lat,
        lng: model.lng,
      );
    });
    results.value = data;
    return data;
  }
}