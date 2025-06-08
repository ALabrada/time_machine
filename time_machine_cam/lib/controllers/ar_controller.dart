import 'dart:async';
import 'dart:math';
import 'package:ar_location_view/ar_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class ARController {
  ARController({
    this.configurationService,
    this.networkService,
    this.maxDistanceInMeters=1000,
  });

  final double maxDistanceInMeters;
  final ConfigurationService? configurationService;
  final NetworkService? networkService;
  final BehaviorSubject<List<ArAnnotation>> annotations = BehaviorSubject();

  StreamSubscription? _eventSubscription;

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> reload() async {
    final position = await Geolocator.getLastKnownPosition();
    await loadPictures(position);
  }

  Future<void> loadPictures(Position? position) async {
    final net = networkService;
    final config = configurationService;
    if (position == null || net == null) {
      annotations.value = [];
      return;
    }
    final results = await net.findNear(
      location: Location(lat: position.latitude, lng: position.longitude),
      radius: max(maxDistanceInMeters, position.accuracy),
      startDate: DateTime(config?.minYear ?? ConfigurationService.defaultMinYear),
      endDate: DateTime(config?.maxYear ?? ConfigurationService.defaultMaxYear),
      sources: config?.providers,
    );

    annotations.value = [
      for (final entry in results.entries)
        for (final item in entry.value)
          PictureAnnotation(
            uid: '${entry.key}/${item.id}',
            picture: item,
            provider: entry.key,
          ),
    ];
  }
}