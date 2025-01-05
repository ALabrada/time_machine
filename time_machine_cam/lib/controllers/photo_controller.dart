import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';

class PhotoController {
  final position = BehaviorSubject<Position>();
  final heading = BehaviorSubject<double>();

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

    headingSubscription = magnetometerEventStream()
      .map(_calculateHeading)
      .listen(heading.add);
    return true;
  }

  double _calculateHeading(MagnetometerEvent event) {
    debugPrint("heading: $event");

    // Calculate direction in radians
    double directionRadians = math.atan2(event.x, event.z);

    // Convert radians to degrees
    double directionDegrees = directionRadians * (180 / math.pi);

    return (directionDegrees + 360) % 360;
  }
}