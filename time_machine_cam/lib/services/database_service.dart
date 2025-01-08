import 'dart:convert';
import 'dart:io';
import 'package:camera_camera/camera_camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:uuid/uuid.dart';

extension CamDatabaseService on DatabaseService {
  Future<Record> createRecord({
    required XFile file,
    Position? position,
    double? heading,
    Picture? original,
  }) async {
    final time = DateTime.now();
    final id = Uuid().v4();
    String url;
    final dirPath = filePath;
    if (dirPath == null) {
      final data = await file.readAsBytes();
      url = 'data:${file.mimeType ?? ''};base64,${base64Encode(data)}';
    } else {
      final localPath = '$dirPath/pictures/$id.jpg';
      await File(localPath).create(recursive: true);
      await File(file.path).copy(localPath);
      // await file.saveTo(localPath);
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
}