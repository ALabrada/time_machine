import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CloudSyncService {
  final DatabaseService db;
  final _eventQueue = <Object>[];

  CloudSyncProvider? _provider;
  StreamSubscription? _cloudSubscription;
  StreamSubscription? _eventSubscription;
  DateTime? _lastChange;
  bool _syncInProgress = false;
  bool _hasPendingChanges = false;
  bool _disposed = false;
  bool _processingEvents = false;

  bool get isActive => _provider != null;

  CloudSyncService({required this.db}) {
    _eventSubscription = db.events.listen(_onDBEvent);
  }

  Future<void> dispose() async {
    _disposed = true;
    _eventSubscription?.cancel();
    _cloudSubscription?.cancel();
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
      return;
    }
    _syncInProgress = true;
    _cloudSubscription?.cancel();
    _cloudSubscription = null;

    try {
      final dt = _lastChange;
      final incomingRecords = await pullRecords(since: dt);
      for (final record in incomingRecords) {
        if (_lastChange == null || record.updateAt.isAfter(_lastChange!)) {
          _lastChange = record.updateAt;
        }
      }

      final outgoingRecords = await db.createRepository<Record>().findUpdatedRecords(since: dt);
      final newestRecord = outgoingRecords.firstOrNull;
      for (final record in outgoingRecords) {
        if (record.cloudId == null) {
          await pushRecord(record);
        } else {
          final incomingRecord = incomingRecords.where((e) => e.cloudId == record.cloudId).firstOrNull;
          if (incomingRecord == null || record.updateAt.isAfter(incomingRecord.updateAt)) {
            await pushRecord(record);
          }
        }
      }

      if (_lastChange == null || newestRecord != null && newestRecord.updateAt.isAfter(_lastChange!)) {
        _lastChange = newestRecord?.updateAt;
      }
    } catch (error) {
      debugPrint("Failed to sync: $error");
    } finally {
      _syncInProgress = false;
    }

    if (_hasPendingChanges) {
      _hasPendingChanges = false;
      unawaited(syncWithCloud());
    } else {
      final provider = _provider;
      if (provider != null && provider.supportsEvents) {
        _cloudSubscription = provider.changes.listen(_onCloudEvent);
      }
    }
  }

  void _onCloudEvent(CloudSyncEvent event) {
    _eventQueue.add(event);
    if (!_processingEvents) {
      _processingEvents = true;
      unawaited(_processQueue());
    }
  }

  void _onDBEvent(event) {
    _eventQueue.add(event);
    if (!_processingEvents) {
      _processingEvents = true;
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    var requiresResync = false;
    while (_eventQueue.isNotEmpty) {
      if (_disposed) break;
      final event = _eventQueue.removeAt(0);
      if (_syncInProgress) {
        _hasPendingChanges = true;
        continue;
      }

      final recordCollection = _provider?.collectionNames[Record];
      try {
        if (event is EntityInserted<Record>) {
          await pushRecord(event.entity);
        } else if (event is EntityUpdated<Record>) {
          await pushRecord(event.entity);
        } else if (event is EntityRemoved<Record>) {
          await deleteRecordFromCould(event.entity);
        } else if (event is CloudReconnectedEvent || event is UnknownEvent) {
          requiresResync = true;
          _eventQueue.clear();
        } else if (event is CloudInsertedEvent && event.collection == recordCollection) {
          if (event.data is Map<String, dynamic>) {
            await _loadRecordFromCloud(event.data!, event.id);
          } else {
            await pullRecord(event.id);
          }
        } else if (event is CloudUpdatedEvent && event.collection == recordCollection) {
          if (event.data is Map<String, dynamic>) {
            await _loadRecordFromCloud(event.data!, event.id);
          } else {
            await pullRecord(event.id);
          }
        } else if (event is CloudDeletedEvent && event.collection == recordCollection) {
          await _deleteRecordFromDB(event.id);
        }
      } catch (_) {
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

    await provider.deleteFile('${item.id.toString()}.jpg');

    final strippedId = _stripPrefix(id);
    if (strippedId != null) {
      await provider.deleteRecord(collection, strippedId);
    }
  }

  Future<void> deleteRecordFromCould(Record item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    final id = item.cloudId;
    if (provider == null || collection == null || id == null) {
      return;
    }

    final picture = item.picture ?? await db.createRepository<Picture>().getById(item.pictureId);
    if (picture != null) {
      await deletePictureFromCloud(picture);
    }

    final strippedId = _stripPrefix(id);
    if (strippedId != null) {
      await provider.deleteRecord(collection, strippedId);
    }
  }

  Future<void> _deleteRecordFromDB(String cloudId) async {
    final repo = db.createRepository<Record>();
    final local = await repo.findRecordByCloudId(cloudId);
    if (local == null) return;

    if (local.pictureId != 0) {
      final pictureRepo = db.createRepository<Picture>();
      final picture = await pictureRepo.getById(local.pictureId);
      if (picture != null) {
        try {
          await db.deleteFiles('pictures/${picture.id}.jpg');
        } catch (_) {}
        await pictureRepo.delete(picture.localId!);
      }
    }
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
    picture.cloudId = id;
    await _downloadPictureFile(picture);
    return await db.createRepository<Picture>().upsert(picture);
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
    Future<Picture?> loadPicture(String cloudId) async {
      final localCopy = await db.createRepository<Picture>().findPictureByCloudId(cloudId);
      if (localCopy == null || await _loadData(localCopy) == null) {
        return await pullPicture(cloudId);
      }
      return localCopy;
    }

    final originalId = json['originalId'];
    final pictureId = json['pictureId'];
    Picture? original, picture;

    if (originalId is String) {
      original = await loadPicture(_addPrefix(originalId));
      json['originalId'] = original?.localId;
    }
    if (pictureId is String) {
      picture = await loadPicture(_addPrefix(pictureId));
      json['pictureId'] = picture?.localId;
    }

    final record = Record.fromJson(json);
    record.original = original;
    record.picture = picture;

    final cloudId = id ?? (record.cloudId != null ? _addPrefix(record.cloudId!) : null);
    if (cloudId != null) {
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
    final store = intMapStoreFactory.store('record');
    await store.record(record.localId!).put(db.db, record.toJson());
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

    if (provider.supportsFiles) {
      final newUrl = await provider.uploadFile(
        name: '${picture.id.toString()}.jpg',
        fileData: data,
        mimeType: 'image/jpg',
      );
      return picture.copy(url: newUrl);
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