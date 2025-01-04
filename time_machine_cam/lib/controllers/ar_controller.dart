import 'dart:async';
import 'package:ar_location_view/ar_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_net/time_machine_net.dart';

class ARController {
  ARController({
    this.networkService,
    this.maxDistanceInMeters=1000,
  });

  final double maxDistanceInMeters;
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
    if (position == null || net == null) {
      annotations.value = [];
      return;
    }
    final results = await net.findNear(
      location: Location(lat: position.latitude, lng: position.longitude),
      radius: position.accuracy + 1000,
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