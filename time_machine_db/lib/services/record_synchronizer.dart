import 'package:time_machine_db/time_machine_db.dart';

class RecordSynchronizer {
  RecordSynchronizer({
    required this.databaseService,
    required this.provider,
    required this.pictures,
    required this.cloudId,
  });

  final DatabaseService databaseService;
  final CloudSyncProvider provider;
  final PictureSynchronizer pictures;
  final String cloudId;

  Repository<T> _createRepository<T>() => Repository<T>.create(db: databaseService.db);

  Future<void> deleteFromCloud(int recordId) async {
    final collection = provider.collectionNames[Record];
    if (collection == null) {
      return;
    }

    final localMirror = await _createRepository<RecordMirror>().findByRecordAndCloud(recordId, cloudId);
    final dt = localMirror?.deletedAt;
    if (localMirror == null || dt == null || dt.isBefore(localMirror.updatedAt)) {
      return;
    }

    localMirror.updatedAt = dt;
    await provider.saveRecord(collection, localMirror.metadata, {});
    await _createRepository<RecordMirror>().update(localMirror);
  }

  Future<RecordMirror?> deleteFromDB(int localId, [DateTime? date]) async {
    final record = await _createRepository<Record>().getById(localId);

    // The record row may already be gone (e.g. deleted via the picture
    // cascade). The mirror must still be tombstoned so the cloud doesn't
    // resurrect the record and the sync cursor advances past this deletion.
    if (record != null) {
      await pictures.deleteFromDB(record.pictureId, date);
    }

    final mirror = await _createRepository<RecordMirror>().findByRecordAndCloud(localId, cloudId);
    if (mirror == null) {
      return null;
    }
    mirror.updatedAt = date ?? DateTime.now();
    mirror.deletedAt = mirror.updatedAt;
    await _createRepository<RecordMirror>().update(mirror);
    if (record != null) {
      await _createRepository<Record>().delete(localId);
    }
    return mirror;
  }

  Future<RecordMirror?> pullRecord(CloudMetadata metadata, [Map<String, dynamic>? data]) async {
    final collection = provider.collectionNames[Record];
    if (collection == null) {
      return null;
    }

    final date = metadata.lastDate;
    var localMirror = await _createRepository<RecordMirror>().findByIdAndCloud(metadata.id, cloudId);
    if (localMirror != null && !date.isAfter(localMirror.lastDate)) {
      localMirror.record = await _createRepository<Record>().getById(localMirror.recordId);
      return localMirror;
    }

    if (metadata.deletedAt != null && localMirror != null) {
      return await deleteFromDB(localMirror.recordId, date);
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
      final mirror = await pictures.pullPicture(originalId, date: date);
      original = mirror?.picture;
      json['originalId'] = original?.localId;
    }
    if (pictureId is String && pictureId.isNotEmpty) {
      final mirror = await pictures.pullPicture(pictureId, date: date);
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
        cloudId: cloudId,
        record: localCopy,
      );
    } else {
      localMirror.updatedAt = date;
      localMirror.record = localCopy;
    }
    return await _createRepository<RecordMirror>().upsert(localMirror);
  }

  Future<RecordMirror?> pushRecord(Record record, [DateTime? date]) async {
    final collection = provider.collectionNames[Record];
    if (collection == null || record.localId == null) {
      return null;
    }

    final json = record.toJson();
    final pictureRepository = _createRepository<Picture>();
    final original = record.original ?? (record.originalId == null
        ? null
        : await pictureRepository.getById(record.originalId!));
    final picture = record.picture ?? await pictureRepository.getById(record.pictureId);

    if (picture == null) {
      return null;
    }

    final originalMirror = original == null ? null : await pictures.pushPicture(original, date);
    final pictureMirror = await pictures.pushPicture(picture);

    if (pictureMirror == null) {
      return null;
    }

    json['originalId'] = originalMirror?.id;
    json['pictureId'] = pictureMirror.id;

    final dt = date ?? DateTime.now();
    var localMirror = await _createRepository<RecordMirror>().findByRecordAndCloud(record.localId!, cloudId);
    if (localMirror == null) {
      localMirror = RecordMirror(
        id: pictures.pictureKey(picture),
        recordId: record.localId!,
        createdAt: dt,
        updatedAt: dt,
        cloudId: cloudId,
        record: record,
      );
    } else if (localMirror.deletedAt == null && localMirror.updatedAt.isBefore(dt)) {
      localMirror.updatedAt = dt;
    }

    localMirror.metadata = await provider.saveRecord(collection, localMirror.metadata, json);
    return await _createRepository<RecordMirror>().upsert(localMirror);
  }
}
