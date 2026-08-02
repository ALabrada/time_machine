import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CloudSyncService {
  final DatabaseService databaseService;
  final _eventQueue = <Object>[];

  CloudSyncProvider? _provider;
  StreamSubscription? _cloudSubscription;
  StreamSubscription? _eventSubscription;
  DateTime? _lastChange;
  bool _syncInProgress = false;
  bool _processingEvents = false;

  PictureSynchronizer? _pictures;
  RecordSynchronizer? _records;

  bool get isActive => _provider != null;
  PictureSynchronizer? get pictures => _pictures;
  RecordSynchronizer? get records => _records;

  CloudSyncService({required this.databaseService}) {
    _eventSubscription = databaseService.events.listen(_onDBEvent);
  }

  Repository<T> _createRepository<T>() => Repository<T>.create(db: databaseService.db);

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

    if (provider == null) {
      _pictures = null;
      _records = null;
    } else {
      final pictures = PictureSynchronizer(databaseService: databaseService, provider: provider);
      _pictures = pictures;
      _records = RecordSynchronizer(databaseService: databaseService, provider: provider, pictures: pictures);
    }

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

    final pictures = _pictures!;
    final records = _records!;

    try {
      final dt = _lastChange;
      final incomingRecords = await _fetchRecords(since: dt);
      for (final record in incomingRecords) {
        await records.pullRecord(record);

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

        final key = localMirror?.id ?? pictures.pictureKey(picture);
        final incomingRecord = incomingRecords
            .where((e) => e.id == key)
            .firstOrNull;
        if (localMirror == null || incomingRecord == null ||
            record.updateAt.isAfter(incomingRecord.lastDate) ||
            record.updateAt.isAfter(localMirror.updatedAt)) {
          final mirror = await records.pushRecord(record);
          if (mirror != null && (_lastChange == null || mirror.lastDate.isAfter(_lastChange!))) {
            _lastChange = mirror.lastDate;
          }
        }
      }

      final deletedPictures = await _createRepository<PictureMirror>().findDeletedRecordsSince(since: dt);
      for (final mirror in deletedPictures) {
        final date = mirror.deletedAt;
        if (date == null || dt != null && !date.isAfter(dt)) {
          continue;
        }
        await pictures.deleteFromDB(mirror.pictureId, date);
        await pictures.deleteFromCloud(mirror.pictureId);
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      final deletedRecords = await _createRepository<RecordMirror>().findDeletedRecordsSince(since: dt);
      for (final mirror in deletedRecords) {
        final date = mirror.deletedAt;
        if (date == null || dt != null && !date.isAfter(dt)) {
          continue;
        }
        await records.deleteFromCloud(mirror.recordId);
        if (_lastChange == null || date.isAfter(_lastChange!)) {
          _lastChange = date;
        }
      }

      _lastChange ??= DateTime.fromMillisecondsSinceEpoch(0);
    } catch (error, stack) {
      debugPrint("Failed to sync: $error\n$stack");
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

      final pictures = _pictures!;
      final records = _records!;

      final recordCollection = _provider?.collectionNames[Record];
      final mirrorRepo = _createRepository<RecordMirror>();
      try {
        if (event is EntityInserted<Record> && await mirrorRepo.findByRecordAndCloud(event.entity.localId!, provider.id) == null && lastChange != null && event.timestamp.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await records.pushRecord(event.entity, event.timestamp);
          _lastChange = ts;
        } else if (event is EntityUpdated<Record> && lastChange != null && event.timestamp.isAfter(lastChange)) {
          final ts = event.entity.updateAt;
          await records.pushRecord(event.entity, event.timestamp);
          _lastChange = ts;
        } else if (event is EntityRemoved<Record>) {
          await deleteRecord(event.entity, event.timestamp);
          await pictures.deleteFromDB(event.entity.pictureId, event.timestamp);
          await pictures.deleteFromCloud(event.entity.pictureId);
          await records.deleteFromCloud(event.entity.localId!);
          if (lastChange != null && event.timestamp.isAfter(lastChange)) {
            _lastChange = event.timestamp;
          }
        } else if (event is CloudReconnectedEvent || event is UnknownEvent) {
          requiresResync = true;
          _eventQueue.clear();
        } else if (event is CloudInsertedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await records.pullRecord(event.metadata, event.data);
          final date = mirror?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudUpdatedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await records.pullRecord(event.metadata, event.data);
          final date = mirror?.lastDate;
          if (date != null && date.isAfter(lastChange)) {
            _lastChange = date;
          }
        } else if (event is CloudDeletedEvent && event.collection == recordCollection && lastChange != null && recordCollection != null) {
          final mirror = await mirrorRepo.findByIdAndCloud(event.metadata.id, provider.id);
          if (mirror == null) {
            continue;
          }
          await records.deleteFromDB(mirror.recordId);
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
}
