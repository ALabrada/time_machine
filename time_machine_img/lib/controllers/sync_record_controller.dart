import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:time_machine_db/time_machine_db.dart';

/// Keeps the single [Record] rendered by a page in sync with the database,
/// reacting to the changes [CloudSyncService] pushes. It only watches
/// [Record]s — the picture page watches [Picture]s on its own controller.
///
/// Cloud sync writes the database directly (through raw repositories
/// that never emit `RepositoryEvent`s), so [CloudSyncService.dbUpdated] — not
/// `DatabaseService.events` — is the change signal the watcher relies on.
///
/// The mixin owns the record state and publishes it to [recordChanges], a
/// broadcast `BehaviorSubject`: views render it with a `StreamBuilder` and, for
/// controllers with an imperative side effect (e.g. the upload form re-filling
/// its inputs via `fillPage`, never reloading the page), [recordChanges] is the
/// notification. On every `dbUpdated` the record is re-read with raw `getById`:
/// - if an already-loaded record disappears, it emits [recordDeleted] once;
/// - otherwise it compares [Record.updateAt] — the only fingerprint — and
///   publishes the record only when it changed, so a cloud sync that changed
///   nothing never causes a visible reload.
///
/// Views never touch the services: they render [recordChanges] and listen to
/// [recordDeleted].
mixin SyncRecordController {
  final _recordController = BehaviorSubject<Record?>();
  final _recordDeletedController = StreamController<void>.broadcast();
  StreamSubscription<void>? _dbUpdatedSubscription;
  DatabaseService? _databaseService;
  int? _watchedEntityId;
  bool _hasRecord = false;
  bool _deleted = false;

  /// The currently loaded record, kept up to date by the watcher.
  Record? record;

  /// Emits the watched record — first load and every content change. The
  /// [Record.updateAt] fingerprint is applied with `distinct`, so records
  /// that did not actually change are never re-published.
  Stream<Record?> get recordChanges => _recordController.stream.distinct(
    (previous, next) => previous?.updateAt == next?.updateAt,
  );

  /// Emits once when the watched record no longer exists.
  Stream<void> get recordDeleted => _recordDeletedController.stream;

  /// Starts watching [entityId] and kicks off the first load. The record's
  /// [Record.updateAt] decides which database state reads as a content change.
  void watchSyncRecord({
    required CloudSyncService? cloudSyncService,
    required DatabaseService? databaseService,
    required int? entityId,
  }) {
    _databaseService = databaseService;
    _watchedEntityId = entityId;
    _hasRecord = false;
    _deleted = false;

    _dbUpdatedSubscription?.cancel();
    _dbUpdatedSubscription = cloudSyncService?.dbUpdated.listen((_) {
      unawaited(_reloadFromDatabase());
    });

    unawaited(_reloadFromDatabase());
  }

  /// Cancels the subscription and closes the streams started by
  /// [watchSyncRecord].
  void disposeSyncRecord() {
    _dbUpdatedSubscription?.cancel();
    _recordDeletedController.close();
    _recordController.close();
  }

  Future<Record?> _loadFromDatabase() async {
    final databaseService = _databaseService;
    final entityId = _watchedEntityId;
    if (databaseService == null || entityId == null) {
      return null;
    }
    final record = await databaseService.createRepository<Record>().getById(entityId);
    if (record == null) {
      return null;
    }
    record.picture = await databaseService
        .createRepository<Picture>()
        .getById(record.pictureId);
    final originalId = record.originalId;
    if (originalId != null) {
      record.original = await databaseService
          .createRepository<Picture>()
          .getById(originalId);
    }
    return record;
  }

  Future<void> _reloadFromDatabase() async {
    if (_deleted || _watchedEntityId == null) {
      return;
    }
    final record = await _loadFromDatabase();
    if (_deleted) {
      return;
    }
    if (record == null) {
      if (_hasRecord) {
        _deleted = true;
        _recordDeletedController.add(null);
      }
      return;
    }
    this.record = record;
    _hasRecord = true;
    _recordController.add(record);
  }
}