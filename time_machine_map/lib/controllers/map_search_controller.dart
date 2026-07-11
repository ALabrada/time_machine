import 'package:flutter/material.dart';
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

  void dispose() {
    results.close();
  }

  Future<void> locate(String name) async {
    final source = configurationService?.geocoder ?? ConfigurationService.defaultGeocoder;
    final result = await networkService?.searchAddress(query: name, source: source) ?? <PlaceInfo>[];
    try {
      final data = List.generate(result.length, (idx) {
        final model = result[idx];
        return PlaceInfo(
          name: model.name,
          lat: model.lat,
          lng: model.lng,
        );
      });
      results.value = data;
    } catch (error) {
      debugPrint("Error: $error");
    }
  }
}