import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:cross_file/cross_file.dart';
import 'package:native_exif/native_exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:uuid/uuid.dart';

extension CamDatabaseService on DatabaseService {
  Future<Record> createRecord({
    required XFile file,
    DateTime? createdAt,
    Position? position,
    double? heading,
    Picture? original,
    double? height,
    double? width,
    BaseCacheManager? cacheManager,
  }) async {
    final time = createdAt ?? DateTime.now();
    var id = Uuid().v4();
    String url;
    var image = await _getImage(file);
    final dirPath = filePath;
    if (dirPath == null || dirPath.isEmpty) {
      final data = img.encodeJpg(image);
      url = 'data:image/jpg;base64,${base64Encode(data)}';
    } else if (p.isWithin(dirPath, file.path)) {
      id = p.basename(file.path);
      url = Uri.file(file.path).toString();
    } else {
      final localPath = '$dirPath/pictures/$id.jpg';
      await File(localPath).create(recursive: true);
      await img.encodeJpgFile(localPath, image);
      url = Uri.file(localPath).toString();
    }
    final pictureViewPort = height == null || width == null
        ? null
        : _getViewPort(image.height.toDouble(), image.width.toDouble(), height, width);

    var picture = Picture(
      id: id,
      provider: '',
      url: url,
      latitude: position?.latitude ?? original?.latitude ?? double.nan,
      longitude: position?.longitude ?? original?.longitude ?? double.nan,
      description: original?.description,
      altitude: position?.altitude ?? original?.altitude,
      bearing: heading ?? position?.heading ?? original?.bearing,
      time: '${time.year}-${time.month}-${time.day}',
    );
    try {
      final place = await Nominatim.reverseSearch(
        lat: picture.latitude,
        lon: picture.longitude,
        language: Intl.defaultLocale,
      );
      picture.description = place.displayName;
    } catch(error) {
      print("Error finding address: $error");
    }

    picture = await createRepository<Picture>().insert(picture);

    String? originalViewPort;
    if (original != null && height != null && width != null) {
      final originalFile = await (cacheManager ?? DefaultCacheManager()).getSingleFile(original.url);
      image = await _getImage(XFile(originalFile.path));
      originalViewPort = _getViewPort(image.height.toDouble(), image.width.toDouble(), height, width);
    }

    final record = Record(
      originalId: original?.localId,
      original: original,
      pictureId: picture.localId!,
      picture: picture,
      width: width,
      height: height,
      originalViewPort: originalViewPort,
      pictureViewPort: pictureViewPort,
      createdAt: time,
      updateAt: time,
    );
    return await createRepository<Record>().insert(record);
  }

  Future<Picture> savePicture(Picture model) async {
    final repo = createRepository<Picture>();
    return await repo.upsert(model);
  }

  Future<img.Image> _getImage(XFile file, {NativeDeviceOrientation? orientation}) async {
    final originalImage = kIsWeb || file.path.isEmpty
        ? img.decodeImage(await file.readAsBytes())
        : await img.decodeImageFile(file.path);
    if (originalImage == null) {
      throw Exception('Invalid image');
    }

    if (orientation == null) {
      return originalImage;
    }

    final qt = turns[orientation];
    if (qt == null || qt == 0) {
      return originalImage;
    }

    return img.copyRotate(originalImage, angle: 90 * qt);
  }

  String _getViewPort(double picHeight, double picWidth, double screenHeight, double screenWidth) {
    final (l, t, w, h) = aspectFitRect(
      width: screenWidth,
      height: screenHeight,
      innerWidth: picWidth,
      innerHeight: picHeight,
    );
    return '$l,$t,$w,$h';
  }
}

Map<NativeDeviceOrientation, int> turns = {
  NativeDeviceOrientation.portraitUp: 0,
  NativeDeviceOrientation.landscapeRight: 1,
  NativeDeviceOrientation.portraitDown: 2,
  NativeDeviceOrientation.landscapeLeft: 3,
};