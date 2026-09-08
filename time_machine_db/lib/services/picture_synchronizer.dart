import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';

class PictureSynchronizer {
  PictureSynchronizer({
    required this.databaseService,
    required this.provider,
    required this.cloudId,
  });

  final DatabaseService databaseService;
  final CloudSyncProvider provider;
  final String cloudId;

  Repository<T> _createRepository<T>() => Repository<T>.create(db: databaseService.db);

  Future<void> deleteFromCloud(int pictureId) async {
    final collection = provider.collectionNames[Picture];
    if (collection == null) {
      return;
    }

    final localMirror = await _createRepository<PictureMirror>().findByPictureAndCloud(pictureId, cloudId);
    final dt = localMirror?.deletedAt;
    if (localMirror == null || dt == null || dt.isBefore(localMirror.updatedAt)) {
      return;
    }

    final key = localMirror.id;
    final cloudJson = await provider.getRecord(collection, key);
    if (cloudJson != null && provider.supportsFiles) {
      try {
        final cloudPicture = Picture.fromJson(cloudJson);
        if (await _loadData(cloudPicture) == null) {
          await provider.deleteFile(cloudPicture.url);
        }
      } catch (_) {}
    }

    localMirror.updatedAt = dt;
    await provider.saveRecord(collection, localMirror.metadata, {});
    await _createRepository<PictureMirror>().update(localMirror);
  }

  Future<PictureMirror?> deleteFromDB(int localId, [DateTime? date]) async {
    final picture = await _createRepository<Picture>().getById(localId);
    if (picture == null) {
      return null;
    }
    try {
      await databaseService.deleteFiles('pictures/${picture.id}.jpg');
    } catch (_) {}
    await _createRepository<Picture>().delete(localId);

    final mirror = await _createRepository<PictureMirror>().findByPictureAndCloud(localId, cloudId);
    if (mirror == null) {
      return null;
    }
    mirror.updatedAt = date ?? DateTime.now();
    mirror.deletedAt = mirror.updatedAt;
    await _createRepository<PictureMirror>().update(mirror);
    return mirror;
  }

  Future<PictureMirror?> pullPicture(String id, {DateTime? date, bool deleted=false}) async {
    Future<Picture> download(Picture picture, int? localId) async {
      final downloaded = await _downloadPictureFile(picture);
      downloaded.localId = localId;
      return await _createRepository<Picture>().upsert(downloaded);
    }

    Future<bool> isDownloaded(Picture? localCopy, String? fileHash) async {
      if (localCopy != null && fileHash != null) {
        final localData = await _loadData(localCopy);
        if (localData != null) {
          final hash = sha256.convert(localData).toString();
          if (hash == fileHash) {
            return true;
          }
        }
      }
      return false;
    }

    final collection = provider.collectionNames[Picture];
    if (collection == null) {
      return null;
    }

    var localMirror = await _createRepository<PictureMirror>().findByIdAndCloud(id, cloudId);
    if (date != null && localMirror != null && !date.isAfter(localMirror.lastDate)) {
      return localMirror;
    }

    final split = _splitPictureKey(id);
    if (split == null) return null;
    final (sourceProvider, sourceId) = split;

    var localCopy = localMirror != null
        ? await _createRepository<Picture>().getById(localMirror.pictureId)
        : await _createRepository<Picture>().findPictureByIdAndProvider(sourceId, sourceProvider);

    if (localCopy != null && deleted) {
      return await deleteFromDB(localCopy.localId!);
    } else if (deleted) {
      return null;
    }

    final json = await provider.getRecord(collection, id);
    if (json == null) {
      return null;
    }
    final picture = Picture.fromJson(json);

    if (!await isDownloaded(localCopy, picture.fileHash)) {
      localCopy = await download(picture, localCopy?.localId);
    } else if (localCopy == null) {
      return null;
    }

    final dt = date ?? DateTime.now();
    if (localMirror == null) {
      localMirror = PictureMirror(
        id: id,
        pictureId: localCopy.localId!,
        createdAt: dt,
        updatedAt: dt,
        cloudId: cloudId,
        picture: localCopy,
      );
    } else {
      localMirror.updatedAt = dt;
      localMirror.picture = localCopy;
    }
    return await _createRepository<PictureMirror>().upsert(localMirror);
  }

  Future<PictureMirror?> pushPicture(Picture picture, [DateTime? date]) async {
    final collection = provider.collectionNames[Picture];
    if (collection == null || picture.localId == null) {
      return null;
    }

    final dt = date ?? DateTime.now();
    var localMirror = await _createRepository<PictureMirror>().findByPictureAndCloud(picture.localId!, cloudId);
    if (localMirror == null) {
      localMirror = PictureMirror(
        id: pictureKey(picture),
        pictureId: picture.localId!,
        createdAt: dt,
        updatedAt: dt,
        cloudId: cloudId,
        picture: picture,
      );
    } else if (localMirror.deletedAt == null && localMirror.updatedAt.isBefore(dt)) {
      localMirror.updatedAt = dt;
    }

    final newPicture = await _uploadPictureFile(picture);
    final json = newPicture.toJson();
    localMirror.metadata = await provider.saveRecord(collection, localMirror.metadata, json);

    return await _createRepository<PictureMirror>().upsert(localMirror);
  }

  Future<Picture> _downloadPictureFile(Picture picture) async {
    var data = await _loadData(picture);

    if (provider.supportsFiles && data == null) {
      data = await provider.downloadFile(picture.url);
    }

    if (data == null) {
      return picture;
    }

    final dirPath = databaseService.filePath;
    if (dirPath == null || dirPath.isEmpty || kIsWeb) {
      return picture.copy(
        url:  Uri.dataFromBytes(data, mimeType: 'image/jpg').toString(),
      );
    } else {
      final localPath = '$dirPath/pictures/${picture.id}.jpg';
      final file = File(localPath);
      await file.create(recursive: true);
      await file.writeAsBytes(data);
      return picture.copy(
        url: Uri.file('$filePathPlaceholder/pictures/${picture.id}.jpg').toString(),
      );
    }
  }

  Future<Picture> _uploadPictureFile(Picture picture) async {
    final data = await _loadData(picture);
    if (data == null) {
      return picture;
    }

    final hash = sha256.convert(data).toString();

    if (provider.supportsFiles) {
      final newUrl = await provider.uploadFile(
        name: '${picture.id.toString()}.jpg',
        fileData: data,
        mimeType: 'image/jpg',
      );
      return picture.copy(url: newUrl, fileHash: hash);
    } else {
      final newUrl = UriData.fromBytes(data).toString();
      return picture.copy(url: newUrl);
    }
  }

  Future<Uint8List?> _loadData(Picture picture) async {
    final url = Uri.tryParse(picture.url);
    if (url == null) {
      return null;
    }
    if (url.isScheme('data')) {
      return UriData.fromUri(url).contentAsBytes();
    }
    if (url.isScheme('file')) {
      final resolvedPath = expandPathGlobal(url.path, databaseService.filePath);
      return await File(resolvedPath).readAsBytes();
    }
    return null;
  }

  String pictureKey(Picture picture) => '${picture.provider}/${picture.id}';

  (String, String)? _splitPictureKey(String key) {
    final index = key.indexOf('/');
    if (index < 0) return null;
    return (key.substring(0, index), key.substring(index + 1));
  }
}
