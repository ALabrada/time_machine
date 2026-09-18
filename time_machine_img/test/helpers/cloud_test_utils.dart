import 'dart:async';
import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

/// In-memory cloud used by the controller tests. It mirrors the shape of the db
/// package's own `MockCloudSyncProvider`, which lives in that package's test
/// directory and cannot be imported from here.
class FakeCloudSyncProvider implements CloudSyncProvider {
  final Map<Type, String> _collectionNames = {};
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, Map<String, CloudMetadata>> _metadata = {};
  final Map<String, Uint8List> _files = {};
  final _changesController = StreamController<CloudSyncEvent>.broadcast();

  FakeCloudSyncProvider({
    Map<Type, String>? collectionNames,
    this.id = '',
    this.supportsEvents = false,
    this.supportsFiles = false,
  }) {
    if (collectionNames != null) {
      _collectionNames.addAll(collectionNames);
    }
  }

  String id;
  @override
  bool supportsEvents;
  @override
  bool supportsFiles;

  @override
  Map<Type, String> get collectionNames => _collectionNames;

  @override
  Future<String> initialize() async => id;

  @override
  Stream<CloudSyncEvent> get changes => _changesController.stream;

  void emitChange([CloudSyncEvent event = const UnknownEvent()]) {
    _changesController.add(event);
  }

  static DateTime? _parseDate(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  CloudMetadata _metadataFromData(String id, Map<String, dynamic> data) {
    final now = DateTime.now();
    final createdAt = _parseDate(data['createdAt']) ?? now;
    final deletedAt = _parseDate(data['deletedAt']);
    final updatedAt = _parseDate(data['updateAt']) ?? deletedAt ?? createdAt;
    return CloudMetadata(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }

  @override
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) async {
    _collections.putIfAbsent(collection, () => {});
    _metadata.putIfAbsent(collection, () => {});
    final recordId = metadata?.id ?? 'cloud_${_collections[collection]!.length}';
    _collections[collection]![recordId] = Map<String, dynamic>.from(data);
    final saved = CloudMetadata(
      id: recordId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (metadata?.createdAt ?? DateTime.now()).millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch),
      deletedAt: metadata?.deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              metadata!.deletedAt!.millisecondsSinceEpoch),
    );
    _metadata[collection]![recordId] = saved;
    return saved;
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final col = _collections[collection];
    if (col == null) {
      return null;
    }
    final data = col[id];
    if (data == null) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<List<CloudMetadata>> listRecords(
    String collection, {
    DateTime? since,
  }) async {
    final col = _collections[collection];
    if (col == null) {
      return [];
    }
    return [
      for (final entry in col.entries)
        _metadata[collection]?[entry.key] ??
            _metadataFromData(entry.key, entry.value),
    ];
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    _collections[collection]?.remove(id);
    _metadata[collection]?.remove(id);
  }

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) async {
    _files[name] = fileData;
    return 'https://cloud.example.com/files/$name';
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    final name = path.split('/').last;
    return _files[name] ?? Uint8List(0);
  }

  @override
  Future<void> deleteFile(String path) async {
    final name = path.split('/').last;
    _files.remove(name);
  }

  void addRecord(String collection, String id, Map<String, dynamic> data) {
    _collections.putIfAbsent(collection, () => {});
    _metadata.putIfAbsent(collection, () => {});
    _collections[collection]![id] = Map<String, dynamic>.from(data);
    _metadata[collection]![id] =
        _metadataFromData(id, _collections[collection]![id]!);
  }

  Map<String, dynamic>? getRecordData(String collection, String id) {
    final data = _collections[collection]?[id];
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  void dispose() {
    _changesController.close();
  }
}

Future<Picture> insertPicture(
  DatabaseService dbService, {
  required String id,
  required String provider,
  String? description,
  DateTime? visitedAt,
}) async {
  final picture = Picture(
    id: id,
    provider: provider,
    url: 'data:image/jpg;base64,AA==',
    latitude: 48.0,
    longitude: 2.0,
    description: description,
    visitedAt: visitedAt ?? DateTime.now(),
  );
  return await dbService.createRepository<Picture>().insert(picture);
}

Future<Record> insertRecord(
  DatabaseService dbService,
  Picture picture, {
  DateTime? updateAt,
  double height = 100,
  double width = 200,
}) async {
  final time = updateAt ?? DateTime.now();
  final record = Record(
    pictureId: picture.localId!,
    createdAt: time,
    updateAt: time,
    height: height,
    width: width,
  );
  return await dbService.createRepository<Record>().insert(record);
}

Map<String, dynamic> cloudPictureJson({
  required String id,
  required String provider,
  String? url,
  String? description,
  DateTime? updateAt,
  DateTime? deletedAt,
}) => {
  'id': id,
  'provider': provider,
  'url': url ?? 'data:image/jpg;base64,AA==',
  'latitude': 48.0,
  'longitude': 2.0,
  if (description != null) 'description': description,
  if (updateAt != null) 'updateAt': updateAt.millisecondsSinceEpoch,
  if (deletedAt != null) 'deletedAt': deletedAt.millisecondsSinceEpoch,
};

Map<String, dynamic> cloudRecordJson({
  required String pictureKey,
  required DateTime updateAt,
  DateTime? createdAt,
  DateTime? deletedAt,
  double height = 100,
  double width = 200,
}) => {
  'pictureId': pictureKey,
  'originalId': null,
  'createdAt': (createdAt ?? updateAt).millisecondsSinceEpoch,
  'updateAt': updateAt.millisecondsSinceEpoch,
  'visitedAt': null,
  'height': height,
  'width': width,
  if (deletedAt != null) 'deletedAt': deletedAt.millisecondsSinceEpoch,
};

CloudMetadata cloudMetadata({
  required String id,
  required DateTime updatedAt,
  DateTime? createdAt,
  DateTime? deletedAt,
}) => CloudMetadata(
  id: id,
  createdAt: createdAt ?? updatedAt,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
);

FakeCloudSyncProvider createTestProvider({String id = 'mock'}) {
  return FakeCloudSyncProvider(
    collectionNames: {Record: 'records', Picture: 'pictures'},
    id: id,
    supportsEvents: true,
  );
}

/// Polls [condition] until it holds or [timeout] milliseconds elapse.
Future<void> waitUntil(
  bool Function() condition, {
  int timeout = 3000,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeout));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}