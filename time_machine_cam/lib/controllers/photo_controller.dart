import 'dart:async';
import 'package:ar_location_view/ar_compass.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:uuid/uuid.dart';

class PhotoController {
  PhotoController({
    this.cacheManager,
    this.configurationService,
    this.databaseService,
    this.networkService,
  });

  final BaseCacheManager? cacheManager;
  final ConfigurationService? configurationService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Picture? original;

  final isProcessing = BehaviorSubject<bool>.seeded(false);
  final position = BehaviorSubject<Position>();
  final heading = BehaviorSubject<double>();
  final orientation = BehaviorSubject<CameraOrientations>();

  StreamSubscription? positionSubscription, headingSubscription;

  double get pictureOpacity => configurationService?.cameraPictureOpacity ?? ConfigurationService.defaultCameraPictureOpacity;
  CameraAspectRatios get cameraMode {
    final ratio =  configurationService?.cameraRatio ?? ConfigurationService.defaultCameraRatio;
    if (ratio == '16x9') {
      return CameraAspectRatios.ratio_16_9;
    } else if (ratio == '4x3') {
      return CameraAspectRatios.ratio_4_3;
    } else if (ratio == '1x1') {
      return CameraAspectRatios.ratio_1_1;
    } else {
      return CameraAspectRatios.ratio_16_9;
    }
  }

  String get targetPath {
    final dirPath = databaseService?.filePath;
    final id = Uuid().v4();
    if (dirPath == null || dirPath.isEmpty) {
      return '$id.jpg';
    }
    return '$dirPath/pictures/$id.jpg';
  }

  Future<void> init() async {
    await subscribeToPosition();
  }

  void dispose() {
    positionSubscription?.cancel();
    headingSubscription?.cancel();
  }

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    original = await databaseService?.createRepository<Picture>().getById(id);
    return original;
  }

  Future<Record?> savePicture({
    required XFile file,
    double? height,
    double? width,
  }) async {
    isProcessing.value = true;
    try {
      final position = this.position.valueOrNull;
      return await databaseService?.createRecord(
        file: file,
        address: await _getAddress(position),
        original: original,
        createdAt: DateTime.now(),
        position: position,
        heading: heading.valueOrNull,
        height: height,
        width: width,
        cacheManager: cacheManager,
      );
    } finally {
      isProcessing.value = false;
    }
  }

  Future<bool> subscribeToPosition() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
    ).listen(position.add);

    final headingStream = FlutterCompass.events;
    if (headingStream != null) {
      headingSubscription = CombineLatestStream.combine2(
          headingStream.mapNotNull((e) => e.heading),
          CamerawesomePlugin.getNativeOrientation() ?? Stream.value(CameraOrientations.portrait_up),
              (trueHeading, orientation) {
            switch (orientation) {
              case CameraOrientations.portrait_up:
                return (trueHeading, orientation);
              case CameraOrientations.portrait_down:
                return (trueHeading + 180, orientation);
              case CameraOrientations.landscape_right:
                return (trueHeading + 90, orientation);
              case CameraOrientations.landscape_left:
                return (trueHeading - 90, orientation);
            }
          })
          .listen((value) {
            heading.add(value.$1);
            orientation.add(value.$2);
          });
    }

    return true;
  }

  Future<String?> _getAddress(Position? position) async {
    if (position == null) {
      return null;
    }
    final source = configurationService?.geocoder ?? ConfigurationService.defaultGeocoder;
    try {
      final places = await networkService?.searchCoordinates(
        coordinates: Location(lat: position.latitude, lng: position.longitude),
        source: source,
      );
      return places?.firstOrNull?.name;
    } catch(error) {
      return null;
    }
  }
}