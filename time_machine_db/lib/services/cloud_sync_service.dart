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

  String? _stripPrefix(String? prefixed) {
    final prefix = _provider?.id;
    if (prefixed == null || prefix == null) return null;
    if (prefix.isEmpty) return prefixed;
    if (prefixed.startsWith(prefix)) return prefixed.substring(prefix.length);
    return null;
  }

  String _addPrefix(String id) {
    final prefix = _provider?.id ?? '';
    return '$prefix$id';
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
      final incomingRecords = await pullRecords(since: dt);
      for (final record in incomingRecords) {
        final date = record.lastDate;
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      final outgoingRecords = await _createRepository<Record>().findUpdatedRecords(since: dt);
      final newestRecord = outgoingRecords.firstOrNull;
      for (final record in outgoingRecords) {
        if (record.cloudId == null) {
          await pushRecord(record);
        } else {
          final incomingRecord = incomingRecords.where((e) => e.cloudId == record.cloudId).firstOrNull;
          if (incomingRecord == null || record.lastDate.isAfter(incomingRecord.lastDate)) {
            await pushRecord(record);
          }
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
    final id = item.cloudId;
    if (provider == null || collection == null || id == null) {
      return;
    }

    final strippedId = _stripPrefix(id);
    if (strippedId == null) {
      return;
    }

    final cloudJson = await provider.getRecord(collection, strippedId);
    if (cloudJson != null) {
      final cloudPicture = Picture.fromJson(cloudJson);
      if (provider.supportsFiles && await _loadData(cloudPicture) == null) {
        try {
          await provider.deleteFile(cloudPicture.url);
        } catch(_) {}
      }
    }

    item.deletedAt = item.deletedAt ?? DateTime.now();
    final json = item.toJson();
    await provider.saveRecord(collection, strippedId, json);
  }

  Future<void> deleteRecordFromCould(Record item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    final id = item.cloudId;
    if (provider == null || collection == null || id == null) {
      return;
    }

    final picture = item.picture ?? await _createRepository<Picture>().getById(item.pictureId);
    if (picture != null) {
      await deletePictureFromCloud(picture);
    }

    final strippedId = _stripPrefix(id);
    if (strippedId != null) {
      item.deletedAt = item.deletedAt ?? DateTime.now();
      final json = item.toJson();
      await provider.saveRecord(collection, strippedId, json);
    }
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

  Future<void> _deleteRecordFromDB(String cloudId) async {
    final repo = _createRepository<Record>();
    final local = await repo.findRecordByCloudId(cloudId);
    if (local == null) return;

    await _deletePictureFromDB(local.picture ?? await _createRepository<Picture>().getById(local.pictureId));
    await repo.delete(local.localId!);
  }

  Future<Picture?> pullPicture(String id) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return null;
    }

    final strippedId = _stripPrefix(id);
    if (strippedId == null) return null;

    final json = await provider.getRecord(collection, strippedId);
    if (json == null) {
      return null;
    }
    final picture = Picture.fromJson(json);
    if (picture.deletedAt != null) {
      final local = await _createRepository<Picture>().findPictureByCloudId(id);
      await _deletePictureFromDB(local);
      return picture;
    }

    final localCopy = await _createRepository<Picture>().findPictureByCloudId(id);
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
    downloaded.cloudId = id;
    return await _createRepository<Picture>().upsert(downloaded);
  }

  Future<Record?> pullRecord(String id) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return null;
    }

    final strippedId = _stripPrefix(id);
    if (strippedId == null) return null;

    final json = await provider.getRecord(collection, strippedId);
    return json is Map<String, dynamic> ? await _loadRecordFromCloud(json, id) : null;
  }

  Future<List<Record>> pullRecords({DateTime? since}) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return [];
    }

    final list = await provider.listRecords(collection, since: since);
    return [
      for (final json in list)
        await _loadRecordFromCloud(json),
    ];
  }

  Future<Record> _loadRecordFromCloud(Map<String, dynamic> json, [String? id]) async {
    final originalId = json['originalId'];
    final pictureId = json['pictureId'];
    Picture? original, picture;

    if (originalId is String) {
      original = await pullPicture(_addPrefix(originalId));
      json['originalId'] = original?.localId;
    }
    if (pictureId is String) {
      picture = await pullPicture(_addPrefix(pictureId));
      json['pictureId'] = picture?.localId;
    }

    final record = Record.fromJson(json);
    record.original = original;
    record.picture = picture;

    final cloudId = id ?? (record.cloudId != null ? _addPrefix(record.cloudId!) : null);
    if (cloudId != null) {
      if (record.deletedAt != null) {
        await _deleteRecordFromDB(cloudId);
        return record;
      }

      final repository = db.createRepository<Record>();
      final localCopy = await repository.findRecordByCloudId(cloudId);

      if (localCopy == null || localCopy.updateAt.isBefore(record.updateAt)) {
        record.localId = localCopy?.localId;
        record.cloudId = cloudId;

        await repository.upsert(record);
      }
    }

    return record;
  }

  Future<bool> pushPicture(Picture picture) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return false;
    }

    final strippedId = _stripPrefix(picture.cloudId);
    if (strippedId != null) {
      return false;
    }

    final newPicture = await _uploadPictureFile(picture);
    final json = newPicture.toJson();
    json['cloudId'] = strippedId;
    final result = await provider.saveRecord(collection, strippedId, json);
    picture.cloudId = _addPrefix(result);
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

    if (original != null && await pushPicture(original)) {
      await pictureRepository.upsert(original);
    }
    if (picture != null && await pushPicture(picture)) {
      await pictureRepository.upsert(picture);
    }

    json['originalId'] = _stripPrefix(original?.cloudId);
    json['pictureId'] = _stripPrefix(picture?.cloudId);
    json['cloudId'] = _stripPrefix(record.cloudId);

    final strippedId = _stripPrefix(record.cloudId);
    final result = await provider.saveRecord(collection, strippedId, json);
    record.cloudId = _addPrefix(result);
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