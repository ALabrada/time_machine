import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CloudSyncService {
  final DatabaseService db;
  final _eventQueue = <Object>[];

  CloudSyncProvider? _provider;
  StreamSubscription? _cloudSubscription;
  StreamSubscription? _eventSubscription;
  DateTime? _lastChange;
  bool _syncInProgress = false;
  bool _processingEvents = false;

  bool get isActive => _provider != null;

  CloudSyncService({required this.db}) {
    _eventSubscription = db.events.listen(_onDBEvent);
  }

  Repository<T> _createRepository<T>() => Repository<T>.create(db: db.db);

  Future<void> dispose() async {
    _eventSubscription?.cancel();
    _cloudSubscription?.cancel();
    _eventQueue.clear();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> setProvider(CloudSyncProvider? provider) async {
    _cloudSubscription?.cancel();
    _cloudSubscription = null;
    _provider = provider;
    _lastChange = null;

    await syncWithCloud();
  }

  Future<void> syncWithCloud() async {
    if (_syncInProgress || _processingEvents) {
      _onCloudEvent(UnknownEvent());
      return;
    }
    _syncInProgress = true;
    _cloudSubscription?.cancel();
    _cloudSubscription = null;

    final cloudId = _provider?.id;
    if (cloudId == null) {
      return;
    }

    try {
      final dt = _lastChange;
      final incomingRecords = await _fetchRecords(since: dt);
      for (final record in incomingRecords) {
        await pullRecord(record);

        final date = record.lastDate;
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      final outgoingRecords = await _createRepository<Record>().findUpdatedRecords(since: dt);
      for (final record in outgoingRecords) {
        final picture = record.picture ?? await _createRepository<Picture>().getById(record.pictureId);
        final localMirror = await _createRepository<RecordMirror>().findByRecordAndCloud(record.localId!, cloudId);
        if (picture == null) {
          continue;
        }

        final key = localMirror?.id ?? _pictureKey(picture);
        final incomingRecord = incomingRecords
            .where((e) => e.id == key)
            .firstOrNull;
        if (localMirror == null || incomingRecord == null ||
            record.updateAt.isAfter(incomingRecord.lastDate) ||
            record.updateAt.isAfter(localMirror.updatedAt)) {
          final mirror = await pushRecord(record);
          if (mirror != null && (_lastChange == null || mirror.lastDate.isAfter(_lastChange!))) {
            _lastChange = mirror.lastDate;
          }
        }
      }

      final deletedPictures = await _createRepository<PictureMirror>().findDeletedRecordsSince(since: dt);
      for (final mirror in deletedPictures) {
        final date = mirror.deletedAt;
        if (date == null || !date.isBefore(mirror.updatedAt)) {
          continue;
        }
        await _deletePictureFromCloud(mirror.pictureId);
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      final deletedRecords = await _createRepository<RecordMirror>().findDeletedRecordsSince(since: dt);
      for (final mirror in deletedRecords) {
        final date = mirror.deletedAt;
        if (date == null || !date.isBefore(mirror.updatedAt)) {
          continue;
        }
        await _deleteRecordFromCloud(mirror.recordId);
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      _lastChange ??= DateTime.fromMillisecondsSinceEpoch(0);
    } catch (error) {
      debugPrint("Failed to sync: $error");
      _lastChange = null;
      _eventQueue.clear();
    } finally {
      _syncInProgress = false;
    }

    if (_eventQueue.isNotEmpty && _lastChange != null) {
      _processingEvents = true;
      unawaited(_processQueue());
    }

    final provider = _provider;
    if (provider != null && provider.supportsEvents) {
      _cloudSubscription = provider.changes.listen(_onCloudEvent);
    }
  }

  Future<List<CloudMetadata>> _fetchRecords({DateTime? since}) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return [];
    }

    final completeList = await provider.listRecords(collection);
    if (since == null) {
      return completeList;
    }

    return [
      for (final item in completeList)
        if (!since.isAfter(item.deletedAt ?? item.updatedAt))
          item,
    ];
  }

  void _onCloudEvent(CloudSyncEvent event) {
    _eventQueue.add(event);
    if (!_processingEvents && !_syncInProgress) {
      _processingEvents = true;
      unawaited(_processQueue());
    }
  }

  void _onDBEvent(event) {
    _eventQueue.add(event);
    if (!_processingEvents && !_syncInProgress) {
      _processingEvents = true;
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    var requiresResync = false;
    while (_eventQueue.isNotEmpty) {
      final event = _eventQueue.removeAt(0);
      final lastChange = _lastChange;

      final provider = _provider;
      if (provider == null) {
        continue;
      }

      final recordCollection = _provider?.collectionNames[Record];
      final mirrorRepo = _createRepository<RecordMirror>();
      try {
        if (event is EntityInserted<Record> && await mirrorRepo.findByRecordAndCloud(event.entity.localId!, provider.id) == null && lastChange != null && event.timestamp.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await pushRecord(event.entity, event.timestamp);
          _lastChange = ts;
        } else if (event is EntityUpdated<Record> && lastChange != null && event.timestamp.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await pushRecord(event.entity, event.timestamp);
          _lastChange = ts;
        } else if (event is EntityRemoved<Record>) {
          await deleteRecord(event.entity, event.timestamp);
          await _deletePictureFromCloud(event.entity.pictureId);
          await _deleteRecordFromCloud(event.entity.localId!);
          if (lastChange != null && event.timestamp.isAfter(lastChange)) {
            _lastChange = event.timestamp;
          }
        } else if (event is CloudReconnectedEvent || event is UnknownEvent) {
          requiresResync = true;
          _eventQueue.clear();
        } else if (event is CloudInsertedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await pullRecord(event.metadata, event.data);
          final date = mirror?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudUpdatedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await pullRecord(event.metadata, event.data);
          final date = mirror?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudDeletedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await mirrorRepo.findByIdAndCloud(event.metadata.id, provider.id);
          if (mirror == null) {
            continue;
          }
          await _deleteRecordFromDB(mirror.recordId);
        }
      } catch (_) {
        _lastChange = null;
      }
    }
    _processingEvents = false;
    if (requiresResync) {
      unawaited(syncWithCloud());
    }
  }
}

extension SyncExtensions on CloudSyncService {
  Future<void> deletePicture(Picture item, [DateTime? date]) async {
    final repository = _createRepository<PictureMirror>();
    final mirrors = await repository.findByPicture(item.localId!);
    if (mirrors.isEmpty) {
      return;
    }

    final dt = date ?? DateTime.now();
    for (final mirror in mirrors) {
      mirror.deletedAt = dt;
      await repository.update(mirror);
    }
  }

  Future<void> deleteRecord(Record item, [DateTime? date]) async {
    if (item.localId == null) {
      return;
    }

    final repository = _createRepository<RecordMirror>();
    final mirrors = await repository.findByRecord(item.localId!);
    if (mirrors.isEmpty) {
      return;
    }

    for (final mirror in mirrors) {
      mirror.deletedAt = date ?? DateTime.now();
      await repository.update(mirror);
    }

    final picture = item.picture ?? await _createRepository<Picture>().getById(item.pictureId);
    if (picture == null) {
      return;
    }

    item.picture = picture;
    await deletePicture(picture);
  }

  Future<void> _deletePictureFromCloud(int pictureId) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return;
    }

    final localMirror = await _createRepository<PictureMirror>().findByPictureAndCloud(pictureId, provider.id);
    final dt = localMirror?.deletedAt;
    if (localMirror == null || dt == null || !dt.isAfter(localMirror.updatedAt)) {
      return;
    }

    final key = localMirror.id;
    final cloudJson = await provider.getRecord(collection, key);
    if (cloudJson != null) {
      final cloudPicture = Picture.fromJson(cloudJson);
      if (provider.supportsFiles && await _loadData(cloudPicture) == null) {
        try {
          await provider.deleteFile(cloudPicture.url);
        } catch(_) {}
      }
    }

    localMirror.updatedAt = dt;
    await provider.saveRecord(collection, localMirror.metadata, {});
    await _createRepository<PictureMirror>().update(localMirror);
  }

  Future<void> _deleteRecordFromCloud(int recordId) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return;
    }

    final localMirror = await _createRepository<RecordMirror>().findByRecordAndCloud(recordId, provider.id);
    final dt = localMirror?.deletedAt;
    if (localMirror == null || dt == null || !dt.isAfter(localMirror.updatedAt)) {
      return;
    }

    localMirror.updatedAt = dt;
    await provider.saveRecord(collection, localMirror.metadata, {});
    await _createRepository<RecordMirror>().update(localMirror);
  }

  Future<PictureMirror?> _deletePictureFromDB(int localId, [DateTime? date]) async {
    final picture = await _createRepository<Picture>().getById(localId);
    final provider = _provider;
    if (picture == null || provider == null) {
      return null;
    }
    try {
      await db.deleteFiles('pictures/${picture.id}.jpg');
    } catch (_) {}
    await _createRepository<Picture>().delete(localId);

    final mirror = await _createRepository<PictureMirror>().findByPictureAndCloud(localId, provider.id);
    if (mirror == null) {
      return null;
    }
    mirror.updatedAt = date ?? DateTime.now();
    mirror.deletedAt = mirror.updatedAt;
    await _createRepository<PictureMirror>().update(mirror);
    return mirror;
  }

  Future<RecordMirror?> _deleteRecordFromDB(int localId, [DateTime? date]) async {
    final record = await _createRepository<Record>().getById(localId);
    final provider = _provider;
    if (record == null || provider == null) {
      return null;
    }

    await _deletePictureFromDB(record.pictureId, date);

    final mirror = await _createRepository<RecordMirror>().findByRecordAndCloud(localId, provider.id);
    if (mirror == null) {
      return null;
    }
    mirror.updatedAt = date ?? DateTime.now();
    mirror.deletedAt = mirror.updatedAt;
    await _createRepository<RecordMirror>().update(mirror);
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

    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return null;
    }
    
    var localMirror = await _createRepository<PictureMirror>().findByIdAndCloud(id, provider.id);
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
      return await _deletePictureFromDB(localCopy.localId!);
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
        cloudId: provider.id,
        picture: localCopy,
      );
    } else {
      localMirror.updatedAt = dt;
      localMirror.picture = localCopy;
    }
    return await _createRepository<PictureMirror>().upsert(localMirror);
  }

  Future<RecordMirror?> pullRecord(CloudMetadata metadata, [Map<String, dynamic>? data]) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return null;
    }

    final date = metadata.lastDate;
    var localMirror = await _createRepository<RecordMirror>().findByIdAndCloud(metadata.id, provider.id);
    if (localMirror != null && !date.isAfter(localMirror.lastDate)) {
      return localMirror;
    }

    if (metadata.deletedAt != null && localMirror != null) {
      return await _deleteRecordFromDB(localMirror.recordId, date);
    } else if (metadata.deletedAt != null) {
      return null;
    }

    final json = data ?? await provider.getRecord(collection, metadata.id);
    if (json == null) {
      return null;
    }

    final originalId = json['originalId'];
    final pictureId = json['pictureId'];
    Picture? original, picture;

    if (originalId is String && originalId.isNotEmpty) {
      final mirror = await pullPicture(originalId, date: date);
      original = mirror?.picture;
      json['originalId'] = original?.localId;
    }
    if (pictureId is String && pictureId.isNotEmpty) {
      final mirror = await pullPicture(pictureId, date: date);
      picture = mirror?.picture;
      json['pictureId'] = picture?.localId;
    }

    final record = Record.fromJson(json);
    record.original = original;
    record.picture = picture;

    Record? localCopy;
    if (localMirror != null) {
      localCopy = await _createRepository<Record>().getById(localMirror.recordId);
    } else if (picture != null && picture.localId != null) {
      localCopy = await _createRepository<Record>().findRecordByPictureId(picture.localId!);
    }

    if (localCopy == null || localCopy.updateAt.isBefore(record.updateAt)) {
      record.localId = localCopy?.localId;
      localCopy = await _createRepository<Record>().upsert(record);
    }

    if (localMirror == null) {
      localMirror = RecordMirror(
        id: metadata.id,
        recordId: localCopy.localId!,
        createdAt: date,
        updatedAt: date,
        cloudId: provider.id,
        record: localCopy,
      );
    } else {
      localMirror.updatedAt = date;
      localMirror.record = localCopy;
    }
    return await _createRepository<RecordMirror>().upsert(localMirror);
  }

  Future<PictureMirror?> pushPicture(Picture picture, [DateTime? date]) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null || picture.localId == null) {
      return null;
    }

    final dt = date ?? DateTime.now();
    var localMirror = await _createRepository<PictureMirror>().findByPictureAndCloud(picture.localId!, provider.id);
    if (localMirror == null) {
      localMirror = PictureMirror(
        id: _pictureKey(picture),
        pictureId: picture.localId!,
        createdAt: dt,
        updatedAt: dt,
        cloudId: provider.id,
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

  Future<RecordMirror?> pushRecord(Record record, [DateTime? date]) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null || record.localId == null) {
      return null;
    }

    final json = record.toJson();
    final pictureRepository = db.createRepository<Picture>();
    final original = record.original ?? (record.originalId == null
        ? null
        : await pictureRepository.getById(record.originalId!));
    final picture = record.picture ?? await pictureRepository.getById(record.pictureId);

    if (picture == null) {
      return null;
    }

    final originalMirror = original == null ? null : await pushPicture(original, date);
    final pictureMirror = await pushPicture(picture);

    if (pictureMirror == null) {
      return null;
    }

    json['originalId'] = originalMirror?.id;
    json['pictureId'] = pictureMirror.id;

    final dt = date ?? DateTime.now();
    var localMirror = await _createRepository<RecordMirror>().findByRecordAndCloud(record.localId!, provider.id);
    if (localMirror == null) {
      localMirror = RecordMirror(
        id: _pictureKey(picture),
        recordId: record.localId!,
        createdAt: dt,
        updatedAt: dt,
        cloudId: provider.id,
        record: record,
      );
    } else if (localMirror.deletedAt == null && localMirror.updatedAt.isBefore(dt)) {
      localMirror.updatedAt = dt;
    }

    localMirror.metadata = await provider.saveRecord(collection, localMirror.metadata, json);
    return await _createRepository<RecordMirror>().upsert(localMirror);
  }

  Future<Picture> _downloadPictureFile(Picture picture) async {
    final provider = _provider;
    if (provider == null) {
      return picture;
    }

    var data = await _loadData(picture);

    if (provider.supportsFiles && data == null) {
      data = await provider.downloadFile(picture.url);
    }

    if (data == null) {
      return picture;
    }

    final dirPath = db.filePath;
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
    final provider = _provider;
    if (provider == null) {
      return picture;
    }

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
      final resolvedPath = expandPathGlobal(url.path, db.filePath);
      return await File(resolvedPath).readAsBytes();
    }
    return null;
  }
}

String _pictureKey(Picture picture) => '${picture.provider}/${picture.id}';

(String, String)? _splitPictureKey(String key) {
  final index = key.indexOf('/');
  if (index < 0) return null;
  return (key.substring(0, index), key.substring(index + 1));
}
