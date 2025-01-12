import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';

class PhotoController {
  final position = BehaviorSubject<Position>();
  final heading = BehaviorSubject<double>();
  final camera = BehaviorSubject<CameraDescription>();

  StreamSubscription? positionSubscription, headingSubscription;

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