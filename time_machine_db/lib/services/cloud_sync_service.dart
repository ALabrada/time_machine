import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CloudSyncService {
  final DatabaseService db;
  final _eventQueue = <RepositoryEvent>[];

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
    _eventSubscription = db.events.listen(_onEvent);
  }

  Future<void> dispose() async {
    _disposed = true;
    _eventSubscription?.cancel();
    _cloudSubscription?.cancel();
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
        _cloudSubscription = provider.changes.listen((_) => syncWithCloud());
      }
    }
  }

  void _onEvent(RepositoryEvent event) {
    _eventQueue.add(event);
    if (!_processingEvents) {
      _processingEvents = true;
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    while (_eventQueue.isNotEmpty) {
      if (_disposed) break;
      final event = _eventQueue.removeAt(0);
      if (_syncInProgress) {
        _hasPendingChanges = true;
        continue;
      }

      try {
        if (event is EntityInserted<Record>) {
          await pushRecord(event.entity);
        } else if (event is EntityUpdated<Record>) {
          await pushRecord(event.entity);
        } else if (event is EntityRemoved<Record>) {
          await deleteRecord(event.entity);
        }
      } catch (error) {
        debugPrint("Failed processing $event: $error");
      }
    }
    _processingEvents = false;
  }
}

extension SyncExtensions on CloudSyncService {
  Future<void> deletePicture(Picture item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    final id = item.cloudId;
    if (provider == null || collection == null || id == null) {
      return;
    }

    await provider.deleteFile('${item.id.toString()}.jpg');
    await provider.deleteRecord(collection, id);
  }

  Future<void> deleteRecord(Record item) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    final id = item.cloudId;
    if (provider == null || collection == null || id == null) {
      return;
    }

    final picture = item.picture ?? await db.createRepository<Picture>().getById(item.pictureId);
    if (picture != null) {
      await deletePicture(picture);
    }

    await provider.deleteRecord(collection, id);
  }

  Future<Picture?> pullPicture(String id) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return null;
    }

    final json = await provider.getRecord(collection, id);
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

    final json = await provider.getRecord(collection, id);
    return json is Map<String, dynamic> ? await _loadRecord(json, id) : null;
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
        await _loadRecord(json),
    ];
  }

  Future<Record> _loadRecord(Map<String, dynamic> json, [String? id]) async {
    Future<Picture?> loadPicture(String cloudId) async {
      final localCopy = await db.createRepository<Picture>().findPictureByCloudId(cloudId);
      return localCopy ?? await pullPicture(cloudId);
    }

    final originalId = json['originalId'];
    final pictureId = json['pictureId'];
    Picture? original, picture;

    if (originalId is String) {
      original = await loadPicture(originalId);
      json['originalId'] = original?.localId;
    }
    if (pictureId is String) {
      picture = await loadPicture(pictureId);
      json['pictureId'] = picture?.localId;
    }

    final record = Record.fromJson(json);
    record.original = original;
    record.picture = picture;

    final cloudId = id ?? record.cloudId;
    if (cloudId != null) {
      final repository = db.createRepository<Record>();
      final localCopy = await repository.findRecordByCloudId(cloudId);

      if (localCopy == null || localCopy.updateAt.isBefore(record.updateAt)) {
        record.localId = localCopy?.localId;
        await repository.upsert(record);
      }
    }

    return record;
  }

  Future<void> pushPicture(Picture picture) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Picture];
    if (provider == null || collection == null) {
      return;
    }

    final newPicture = await _uploadPictureFile(picture);
    picture.cloudId = await provider.saveRecord(collection, newPicture.cloudId, newPicture.toJson());
  }

  Future<void> pushRecord(Record record) async {
    final provider = _provider;
    final collection = _provider?.collectionNames[Record];
    if (provider == null || collection == null) {
      return;
    }

    final json = record.toJson();
    final pictureRepository = db.createRepository<Picture>();
    final original = record.original ?? (record.originalId == null
        ? null
        : await pictureRepository.getById(record.originalId!));
    final picture = record.picture ?? await pictureRepository.getById(record.pictureId);

    if (original != null && original.cloudId == null) {
      await pushPicture(original);
      await pictureRepository.upsert(original);
    }
    if (picture != null && picture.cloudId == null) {
      await pushPicture(picture);
      await pictureRepository.upsert(picture);
    }

    json['originalId'] = original?.cloudId;
    json['pictureId'] = picture?.cloudId;

    record.cloudId = await provider.saveRecord(collection, record.cloudId, json);
    await db.createRepository<Record>().update(record);
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