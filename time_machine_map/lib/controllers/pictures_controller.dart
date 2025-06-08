import 'dart:async';
import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
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
    unawaited(_subscribePositionIfAvailable());
  }

  final ConfigurationService? configurationService;
  final MapController? mapController;
  final NetworkService? networkService;
  final SharedPreferencesWithCache? preferences;

  final BehaviorSubject<bool> isProcessing = BehaviorSubject.seeded(false);
  final BehaviorSubject<List<Picture>> pictures = BehaviorSubject();
  final BehaviorSubject<Picture?> selection = BehaviorSubject.seeded(null);
  final BehaviorSubject<Position?> position = BehaviorSubject.seeded(null);

  StreamSubscription? _eventSubscription, _positionSubscription;

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
    _positionSubscription?.cancel();
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

    isProcessing.value = true;
    try {
      var position = this.position.valueOrNull;
      if (position == null) {
        var permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            return false;
          }
        }

        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        _subscribePosition(serviceEnabled: serviceEnabled);

        if (!serviceEnabled) {
          await Geolocator.openLocationSettings();
          return false;
        }

        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(accuracy: LocationAccuracy.best),
        );
      }

      final coord = LatLng(position.latitude, position.longitude);
      if (mapController.move(coord, max(mapController.camera.zoom, 17.0))) {
        saveSettings(mapController.camera);
        return true;
      }

      return false;
    } finally {
      isProcessing.value = false;
    }
  }

  Future<bool> _subscribePositionIfAvailable() async {
    var permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      return false;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    _subscribePosition(serviceEnabled: serviceEnabled);
    return true;
  }

  void _subscribePosition({bool serviceEnabled=false}) {
    _positionSubscription = Geolocator.getServiceStatusStream().mergeWith([
      Stream.value(serviceEnabled ? ServiceStatus.enabled : ServiceStatus.disabled),
    ])
      .flatMap((s) {
        if (s == ServiceStatus.enabled) {
          return Geolocator.getPositionStream(
            locationSettings: LocationSettings(accuracy: LocationAccuracy.best),
          );
        }
        return Stream.value(null);
      })
      .listen(position.add);
  }
}