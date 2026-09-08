import 'dart:async';
import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

class MockCloudSyncProvider implements CloudSyncProvider {
  final Map<Type, String> _collectionNames = {};
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, Map<String, CloudMetadata>> _metadata = {};
  final Map<String, Uint8List> _files = {};
  final _changesController = StreamController<CloudSyncEvent>.broadcast();

  String id = '';
  bool failInitialize = false;

  @override
  Future<String> initialize() async {
    if (failInitialize) {
      throw Exception('Failed to initialize');
    }
    return id;
  }

  @override
  bool supportsEvents = false;

  @override
  bool supportsFiles = false;

  String? lastUploadedFileName;
  Uint8List? lastUploadedFileData;
  String? lastDownloadedFilePath;

  MockCloudSyncProvider({
    Map<Type, String>? collectionNames,
    this.id = '',
    this.supportsEvents = false,
    this.supportsFiles = false,
  }) {
    if (collectionNames != null) {
      _collectionNames.addAll(collectionNames);
    }
  }

  @override
  Map<Type, String> get collectionNames => _collectionNames;

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
      createdAt: metadata?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: metadata?.deletedAt,
    );
    _metadata[collection]![recordId] = saved;
    return saved;
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final col = _collections[collection];
    if (col == null) return null;
    final data = col[id];
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection, {DateTime? since}) async {
    final col = _collections[collection];
    if (col == null) return [];
    return [
      for (final entry in col.entries)
        _metadata[collection]?[entry.key] ?? _metadataFromData(entry.key, entry.value),
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
    lastUploadedFileName = name;
    lastUploadedFileData = fileData;
    _files[name] = fileData;
    return 'https://cloud.example.com/files/$name';
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    lastDownloadedFilePath = path;
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
    _metadata[collection]![id] = _metadataFromData(id, _collections[collection]![id]!);
  }

  void addFile(String name, Uint8List data) {
    _files[name] = data;
  }

  bool hasRecord(String collection, String id) {
    final metadata = _metadata[collection]?[id];
    if (metadata == null) return false;
    return metadata.deletedAt == null;
  }

  Map<String, dynamic>? getRecordData(String collection, String id) {
    final data = _collections[collection]?[id];
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  CloudMetadata? getMetadata(String collection, String id) {
    return _metadata[collection]?[id];
  }

  int getCollectionSize(String collection) {
    return _collections[collection]?.length ?? 0;
  }

  void dispose() {
    _changesController.close();
  }
}
