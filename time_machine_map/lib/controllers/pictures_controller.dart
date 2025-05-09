import 'dart:async';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class PicturesController {
  PicturesController({
    this.configurationService,
    this.mapController,
    this.networkService,
    this.preferences,
  }) {
    _eventSubscription = mapController?.mapEventStream
      .throttleTime(Duration(seconds: 1))
      .listen((e) {
        saveSettings(e.camera);
        unawaited(loadPictures(e.camera));
      });
  }

  final ConfigurationService? configurationService;
  final MapController? mapController;
  final NetworkService? networkService;
  final SharedPreferencesWithCache? preferences;
  final BehaviorSubject<List<Picture>> pictures = BehaviorSubject();
  final BehaviorSubject<Picture?> selection = BehaviorSubject.seeded(null);

  StreamSubscription? _eventSubscription;

  LatLng? get defaultCenter {
    final lat = preferences?.getDouble('map.lat');
    final lng = preferences?.getDouble('map.lng');
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return null;
  }
  double? get defaultRotation => preferences?.getDouble('map.rotation');
  double? get defaultZoom => preferences?.getDouble('map.zoom');

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> reload() => loadPictures(mapController?.camera);

  void saveSettings(MapCamera camera) {
    preferences?.setDouble('map.lat', camera.center.latitude);
    preferences?.setDouble('map.lng', camera.center.longitude);
    preferences?.setDouble('map.zoom', camera.zoom);
    preferences?.setDouble('map.rotation', camera.rotation);
  }

  Future<void> loadPictures(MapCamera? camera) async {
    final net = networkService;
    final config = configurationService;
    if (camera == null || net == null || camera.zoom <= 10.0) {
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
    final results = await net.findIn(
      area: area,
      startDate: DateTime(config?.minYear ?? ConfigurationService.defaultMinYear),
      endDate: DateTime(config?.maxYear ?? ConfigurationService.defaultMaxYear),
      sources: config?.providers,
    );
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
    if (mapController.move(coord, max(mapController.camera.zoom, 17.0))) {
      saveSettings(mapController.camera);
      return true;
    }

    return false;
  }
}