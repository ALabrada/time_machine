import 'dart:async';
import 'package:ar_location_view/ar_compass.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:time_machine_config/time_machine_config.dart';

class PhotoController {
  PhotoController({
    this.configurationService,
  });

  final ConfigurationService? configurationService;

  final position = BehaviorSubject<Position>();
  final heading = BehaviorSubject<double>();

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

    final headingStream = FlutterCompass.events;
    if (headingStream != null) {
      headingSubscription = CombineLatestStream.combine2(
          headingStream.mapNotNull((e) => e.heading),
          NativeDeviceOrientationCommunicator().onOrientationChanged(useSensor: true),
              (trueHeading, orientation) {
            switch (orientation) {
              case NativeDeviceOrientation.portraitUp:
                return trueHeading;
              case NativeDeviceOrientation.portraitDown:
                return trueHeading + 180;
              case NativeDeviceOrientation.landscapeRight:
                return trueHeading + 90;
              case NativeDeviceOrientation.landscapeLeft:
                return trueHeading - 90;
              default:
                return trueHeading;
            }
          })
          .listen(heading.add);
    }

    return true;
  }
}