import 'dart:async';
import 'package:camera/camera.dart';
import 'package:camera_camera/camera_camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_config/time_machine_config.dart';

class PhotoController {
  PhotoController({
    this.configurationService,
  });

  final ConfigurationService? configurationService;

  final position = BehaviorSubject<Position>();
  final heading = BehaviorSubject<double>();
  final camera = BehaviorSubject<CameraDescription>();

  StreamSubscription? positionSubscription, headingSubscription;

  double get pictureOpacity => configurationService?.cameraPictureOpacity ?? ConfigurationService.defaultCameraPictureOpacity;
  CameraMode get cameraMode {
    final ratio =  configurationService?.cameraRatio ?? ConfigurationService.defaultCameraRatio;
    if (ratio == '16x9') {
      return CameraMode.ratio16s9;
    } else if (ratio == '4x3') {
      return CameraMode.ratio4s3;
    } else if (ratio == '1x1') {
      return CameraMode.ratio1s1;
    } else {
      return CameraMode.ratioFull;
    }
  }

  Future<void> init() async {
    await subscribeToPosition();
  }

  void dispose() {
    positionSubscription?.cancel();
    headingSubscription?.cancel();
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

    headingSubscription = FlutterCompass.events?.mapNotNull((e) => e.heading)
        .listen(heading.add);

    return true;
  }
}