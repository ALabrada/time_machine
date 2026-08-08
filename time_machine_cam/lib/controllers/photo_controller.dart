import 'dart:async';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:uuid/uuid.dart';

class PhotoController {
  PhotoController({
    required this.cacheService,
    this.configurationService,
    this.databaseService,
    this.networkService,
  });

  final CacheService cacheService;
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

  String get cameraRatioString {
    return configurationService?.cameraRatio ?? ConfigurationService.defaultCameraRatio;
  }

  String get targetPath {
    final dirPath = databaseService?.filePath;
    const uuid = Uuid();
    final id = uuid.v4();
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
    isProcessing.close();
    position.close();
    heading.close();
    orientation.close();
  }

  Stream<NativeDeviceOrientation> _nativeOrientationStream() {
    return NativeDeviceOrientationCommunicator().onOrientationChanged();
  }

  double _headingOffset(NativeDeviceOrientation orientation) {
    switch (orientation) {
      case NativeDeviceOrientation.portraitUp:
      case NativeDeviceOrientation.unknown:
        return 0;
      case NativeDeviceOrientation.portraitDown:
        return 180;
      case NativeDeviceOrientation.landscapeRight:
        return 90;
      case NativeDeviceOrientation.landscapeLeft:
        return -90;
    }
  }

  CameraOrientations _toCameraOrientations(NativeDeviceOrientation orientation) {
    switch (orientation) {
      case NativeDeviceOrientation.portraitUp:
        return CameraOrientations.portrait_up;
      case NativeDeviceOrientation.portraitDown:
        return CameraOrientations.portrait_down;
      case NativeDeviceOrientation.landscapeLeft:
        return CameraOrientations.landscape_left;
      case NativeDeviceOrientation.landscapeRight:
        return CameraOrientations.landscape_right;
      case NativeDeviceOrientation.unknown:
        return CameraOrientations.portrait_up;
    }
  }

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    original = await databaseService?.loadPicture(id);
    return original;
  }

  Future<Record?> savePicture({
    required XFile file,
    double? height,
    double? width,
    NativeDeviceOrientation? orientation,
    double? aspectRatio,
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
        orientation: orientation,
        aspectRatio: aspectRatio,
        cacheService: cacheService,
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
          headingStream.mapNotNull((e) {
            final accuracy = e.accuracy;
            if (accuracy != null && accuracy > 50) {
              return null;
            }
            return e.heading;
          }),
          _nativeOrientationStream(),
              (trueHeading, orientation) {
            final corrected = trueHeading + _headingOffset(orientation);
            return (corrected % 360, _toCameraOrientations(orientation));
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