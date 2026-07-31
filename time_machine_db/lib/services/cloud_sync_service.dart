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

    try {
      final dt = _lastChange;
      final incomingRecords = await pullRecords();
      for (final record in incomingRecords) {
        final date = record.lastDate;
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      final outgoingRecords = await _createRepository<Record>().findUpdatedRecords(since: dt);
      final newestRecord = outgoingRecords.firstOrNull;
      final providerId = _provider?.id;
      for (final record in outgoingRecords) {
        final picture = record.picture ?? await _createRepository<Picture>().getById(record.pictureId);
        if (picture == null) {
          continue;
        }

        final key = _pictureKey(picture);
        final incomingRecord = incomingRecords
            .where((e) => e.picture != null && _pictureKey(e.picture!) == key)
            .firstOrNull;
        if (record.cloudId != providerId ||
            incomingRecord == null ||
            record.lastDate.isAfter(incomingRecord.lastDate)) {
          await pushRecord(record);
        }
      }

      final date = newestRecord?.lastDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (_lastChange == null || date.isAfter(_lastChange!)) {
        _lastChange = date;
      }
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

      final recordCollection = _provider?.collectionNames[Record];
      try {
        if (event is EntityInserted<Record> && event.entity.cloudId == null && lastChange != null && event.entity.updateAt.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await pushRecord(event.entity);
          _lastChange = ts;
        } else if (event is EntityUpdated<Record> && lastChange != null && event.entity.updateAt.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await pushRecord(event.entity);
          _lastChange = ts;
        } else if (event is EntityRemoved<Record> && event.entity.deletedAt != null) {
          if (lastChange != null && event.entity.deletedAt!.isAfter(lastChange)) {
            await deleteRecordFromCould(event.entity);
            _lastChange = event.entity.deletedAt!;
          } else if (event.entity.cloudId != null) {
            event.entity.localId = null;
            _createRepository<Record>().insert(event.entity);
          }
        } else if (event is CloudReconnectedEvent || event is UnknownEvent) {
          requiresResync = true;
          _eventQueue.clear();
        } else if (event is CloudInsertedEvent && event.collection == recordCollection && lastChange != null) {
          Record? record;
          if (event.data is Map<String, dynamic>) {
            record = await _loadRecordFromCloud(event.data!, event.id);
          } else {
            record = await pullRecord(event.id);
          }
          final date = record?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudUpdatedEvent && event.collection == recordCollection && lastChange != null) {
          Record? record;
          if (event.data is Map<String, dynamic>) {
            record = await _loadRecordFromCloud(event.data!, event.id);
          } else {
            record = await pullRecord(event.id);
          }
          final date = record?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudDeletedEvent && event.collection == recordCollection && lastChange != null) {
          await _deleteRecordFromDB(event.id);
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
  Future<void> deletePictureFromCloud(Picture item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null || item.cloudId != provider.id) {
      return;
    }

    final key = _pictureKey(item);
    final cloudJson = await provider.getRecord(collection, key);
    if (cloudJson != null) {
      final cloudPicture = Picture.fromJson(cloudJson);
      if (provider.supportsFiles && await _loadData(cloudPicture) == null) {
        try {
          await provider.deleteFile(cloudPicture.url);
        } catch(_) {}
      }
    }

    item.deletedAt = item.deletedAt ?? DateTime.now();
    final json = item.toJson()..remove('cloudId');
    await provider.saveRecord(collection, key, json);
  }

  Future<void> deleteRecordFromCould(Record item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null || item.cloudId != provider.id) {
      return;
    }

    final picture = item.picture ?? await _createRepository<Picture>().getById(item.pictureId);
    if (picture == null) {
      return;
    }

    await deletePictureFromCloud(picture);

    item.deletedAt = item.deletedAt ?? DateTime.now();
    final json = item.toJson()
      ..remove('cloudId')
      ..['pictureId'] = _pictureKey(picture);
    await provider.saveRecord(collection, _pictureKey(picture), json);
  }

  Future<void> _deletePictureFromDB(Picture? picture) async {
    if (picture == null || picture.localId == null) {
      return;
    }
    try {
      await db.deleteFiles('pictures/${picture.id}.jpg');
    } catch (_) {}
    await _createRepository<Picture>().delete(picture.localId!);
  }

  Future<void> _deleteRecordFromDB(String pictureKey) async {
    final split = _splitPictureKey(pictureKey);
    if (split == null) return;
    final (sourceProvider, sourceId) = split;

    final pictureRepository = _createRepository<Picture>();
    final picture = await pictureRepository.findPictureByIdAndProvider(sourceId, sourceProvider);
    if (picture == null || picture.localId == null) return;

    final recordRepository = _createRepository<Record>();
    final local = await recordRepository.findRecordByPictureId(picture.localId!);
    if (local == null) return;

    await _deletePictureFromDB(local.picture ?? picture);
    await recordRepository.delete(local.localId!);
  }

  Future<Picture?> pullPicture(String id) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return null;
    }

    final split = _splitPictureKey(id);
    if (split == null) return null;
    final (sourceProvider, sourceId) = split;

    final json = await provider.getRecord(collection, id);
    if (json == null) {
      return null;
    }
    final picture = Picture.fromJson(json);
    final localCopy = await _createRepository<Picture>().findPictureByIdAndProvider(sourceId, sourceProvider);

    if (picture.deletedAt != null) {
      await _deletePictureFromDB(localCopy);
      return picture;
    }

    if (localCopy != null && picture.fileHash != null) {
      final localData = await _loadData(localCopy);
      if (localData != null) {
        final hash = sha256.convert(localData).toString();
        if (hash == picture.fileHash) {
          return localCopy;
        }
      }
    }

    final downloaded = await _downloadPictureFile(picture);
    downloaded.cloudId = provider.id;
    downloaded.localId = localCopy?.localId;
    return await _createRepository<Picture>().upsert(downloaded);
  }

  Future<Record?> pullRecord(String id) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return null;
    }

    final json = await provider.getRecord(collection, id);
    return json is Map<String, dynamic> ? await _loadRecordFromCloud(json) : null;
  }

  Future<List<Record>> pullRecords() async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return [];
    }

    final list = await provider.listRecords(collection);
    return [
      for (final json in list)
        await _loadRecordFromCloud(json),
    ];
  }

  Future<Record> _loadRecordFromCloud(Map<String, dynamic> json, [String? id]) async {
    final originalId = json['originalId'];
    final pictureId = json['pictureId'];
    Picture? original, picture;

    if (originalId is String && originalId.isNotEmpty) {
      original = await pullPicture(originalId);
      json['originalId'] = original?.localId;
    }
    if (pictureId is String && pictureId.isNotEmpty) {
      picture = await pullPicture(pictureId);
      json['pictureId'] = picture?.localId;
    }

    final record = Record.fromJson(json);
    record.original = original;
    record.picture = picture;

    final key = pictureId is String && pictureId.isNotEmpty ? pictureId : id;
    if (key == null || key.isEmpty) {
      return record;
    }

    if (record.deletedAt != null) {
      await _deleteRecordFromDB(key);
      return record;
    }

    if (picture != null && picture.localId != null) {
      final repository = db.createRepository<Record>();
      final localCopy = await repository.findRecordByPictureId(picture.localId!);

      if (localCopy == null || localCopy.updateAt.isBefore(record.updateAt)) {
        record.localId = localCopy?.localId;
        record.cloudId = _provider?.id;
        await repository.upsert(record);
      }
    }

    return record;
  }

  Future<bool> pushPicture(Picture picture) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null || picture.cloudId == provider.id) {
      return false;
    }

    final newPicture = await _uploadPictureFile(picture);
    final json = newPicture.toJson()..remove('cloudId');
    await provider.saveRecord(collection, _pictureKey(picture), json);
    picture.cloudId = provider.id;
    await _createRepository<Picture>().upsert(picture);
    return true;
  }

  Future<bool> pushRecord(Record record) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return false;
    }

    final json = record.toJson();
    final pictureRepository = db.createRepository<Picture>();
    final original = record.original ?? (record.originalId == null
        ? null
        : await pictureRepository.getById(record.originalId!));
    final picture = record.picture ?? await pictureRepository.getById(record.pictureId);

    if (picture == null) {
      return false;
    }

    if (original != null && await pushPicture(original)) {
      await pictureRepository.upsert(original);
    }
    if (await pushPicture(picture)) {
      await pictureRepository.upsert(picture);
    }

    json['originalId'] = original == null ? null : _pictureKey(original);
    json['pictureId'] = _pictureKey(picture);
    json.remove('cloudId');

    await provider.saveRecord(collection, _pictureKey(picture), json);
    record.cloudId = provider.id;
    await _createRepository<Record>().upsert(record);
    return true;
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
