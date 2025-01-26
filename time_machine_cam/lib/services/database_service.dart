import 'dart:convert';
import 'dart:io';
import 'package:camera_camera/camera_camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:uuid/uuid.dart';

extension CamDatabaseService on DatabaseService {
  Future<Record> createRecord({
    required XFile file,
    Position? position,
    double? heading,
    Picture? original,
  }) async {
    final orientation = await NativeDeviceOrientationCommunicator().orientation();
    final time = DateTime.now();
    final id = Uuid().v4();
    String url;
    final image = await _getImage(file, orientation: orientation);
    final dirPath = filePath;
    if (dirPath == null) {
      final data = img.encodeJpg(image);
      url = 'data:image/jpg;base64,${base64Encode(data)}';
    } else {
      final localPath = '$dirPath/pictures/$id.jpg';
      await File(localPath).create(recursive: true);
      await img.encodeJpgFile(localPath, image);
      url = Uri.file(localPath).toString();
    }

    var picture = Picture(
      id: id,
      provider: '',
      url: url,
      latitude: position?.latitude ?? original?.latitude ?? double.nan,
      longitude: position?.longitude ?? original?.latitude ?? double.nan,
      description: original?.description,
      altitude: position?.altitude ?? original?.altitude,
      bearing: heading ?? position?.heading ?? original?.bearing,
      time: '${time.year}-${time.month}-${time.day}',
    );
    try {
      final place = await Nominatim.reverseSearch(
        lat: picture.latitude,
        lon: picture.longitude,
      );
      picture.description = place.displayName;
    } catch(error) {
      print("Error finding address: $error");
    }

    picture = await createRepository<Picture>().insert(picture);

    final record = Record(
      originalId: original?.localId,
      original: original,
      pictureId: picture.localId!,
      picture: picture,
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
    final originalImage = img.decodeImage(await file.readAsBytes());
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
}

Map<NativeDeviceOrientation, int> turns = {
  NativeDeviceOrientation.portraitUp: 0,
  NativeDeviceOrientation.landscapeRight: 1,
  NativeDeviceOrientation.portraitDown: 2,
  NativeDeviceOrientation.landscapeLeft: 3,
};