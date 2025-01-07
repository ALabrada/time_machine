import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class PicturesController {
  PicturesController({
    this.mapController,
    this.networkService,
  }) {
    _eventSubscription = mapController?.mapEventStream
      .throttleTime(Duration(seconds: 1))
      .listen((e) {
        unawaited(loadPictures(e.camera));
      });
  }

  final MapController? mapController;
  final NetworkService? networkService;
  final BehaviorSubject<List<Picture>> pictures = BehaviorSubject();
  final BehaviorSubject<Picture?> selection = BehaviorSubject.seeded(null);

  StreamSubscription? _eventSubscription;

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> reload() => loadPictures(mapController?.camera);

  Future<void> loadPictures(MapCamera? camera) async {
    final net = networkService;
    if (camera == null || net == null) {
      pictures.value = [];
      return;
    }
    final bounds = camera.visibleBounds;
    final area = Area(
      minLat: bounds.south,
      minLng: bounds.west,
      maxLat: bounds.north,
      maxLng: bounds.east,
      zoom: camera.zoom,
    );
    final location = Location(lat: camera.center.latitude, lng: camera.center.longitude);
    final diameter = Distance().as(LengthUnit.Meter, LatLng(bounds.south, bounds.east), LatLng(bounds.north, bounds.west));
    // final results = await net.findIn(area: area);
    final results = await net.findNear(location: location, radius: diameter / 2.0);
    pictures.value = [
      for (final result in results.values)
        for (final item in result)
          item,
    ];
  }

  Future<bool> moveToCurrentLocation() async {
    final mapController = this.mapController;
    if (mapController == null) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return false;
      }
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    final position = await Geolocator.getCurrentPosition();
    final coord = LatLng(position.latitude, position.longitude);
    return mapController.move(coord, mapController.camera.zoom);
  }
}