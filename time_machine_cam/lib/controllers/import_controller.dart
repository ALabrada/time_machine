import 'package:custom_image_crop/custom_image_crop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class ImportController {
  ImportController({
    this.configurationService,
    this.databaseService,
    this.networkService,
    this.original,
  });

  final cropController = CustomImageCropController();

  final ConfigurationService? configurationService;
  final DatabaseService? databaseService;
  final NetworkService? networkService;
  Picture? original;
  XFile? selection;

  double get pictureOpacity => configurationService?.cameraPictureOpacity ?? ConfigurationService.defaultCameraPictureOpacity;

  Future<Picture?> loadPicture(int? id) async {
    if (id == null) {
      return null;
    }
    original = await databaseService?.createRepository<Picture>().getById(id);
    return original;
  }

  Future<Record?> importPicture({
    double? height,
    double? width,
    BaseCacheManager? cacheManager,
  }) async {
    final selection = this.selection;
    final result = await cropController.onCropImage();
    if (result == null || selection == null) {
      return null;
    }
    final (lat, lng, time) = await _readExif(selection);
    return await databaseService?.createRecord(
      file: XFile.fromData(result.bytes),
      original: original,
      createdAt: time,
      position: lat == null || lng == null ? null : Position(
        longitude: lng,
        latitude: lat,
        timestamp: time ?? DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
      height: height,
      width: width,
      cacheManager: cacheManager,
    );
  }

  Future<XFile?> pickImage() async {
    if (selection != null) {
      return selection;
    }
    selection = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    return selection;
  }

  Future<(double? latitude, double? longitude, DateTime? dateTime)> _readExif(XFile file) async {
    if (kIsWeb) {
      return (null, null, null);
    }
    final tags = await Exif.fromPath(file.path);
    final coord = await tags.getLatLong();
    final dateTime = await tags.getOriginalDate();
    return (coord?.latitude, coord?.longitude, dateTime);
  }
}