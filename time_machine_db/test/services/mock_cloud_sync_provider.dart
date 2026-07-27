import 'dart:async';
import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

class MockCloudSyncProvider implements CloudSyncProvider {
  final Map<Type, String> _collectionNames = {};
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, Uint8List> _files = {};
  final _changesController = StreamController<CloudSyncEvent>.broadcast();

  @override
  bool supportsEvents = false;

  @override
  bool supportsFiles = false;

  String? lastUploadedFileName;
  Uint8List? lastUploadedFileData;
  String? lastDownloadedFilePath;

  MockCloudSyncProvider({
    Map<Type, String>? collectionNames,
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

  @override
  Future<String> saveRecord(String collection, String? id, Map<String, dynamic> data) async {
    _collections.putIfAbsent(collection, () => {});
    final recordId = id ?? 'cloud_${_collections[collection]!.length}';
    data = Map<String, dynamic>.from(data);
    _collections[collection]![recordId] = data;
    return recordId;
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
  Future<List<Map<String, dynamic>>> listRecords(String collection, {DateTime? since}) async {
    final col = _collections[collection];
    if (col == null) return [];
    final records = col.entries.map((e) {
      final data = Map<String, dynamic>.from(e.value);
      data['cloudId'] = e.key;
      return data;
    }).where((data) {
      if (since == null) return true;
      final updateAt = data['updateAt'];
      if (updateAt is int) {
        return DateTime.fromMillisecondsSinceEpoch(updateAt).isAfter(since);
      }
      return true;
    }).toList();
    return records;
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    _collections[collection]?.remove(id);
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
    _collections[collection]![id] = Map<String, dynamic>.from(data);
  }

  void addFile(String name, Uint8List data) {
    _files[name] = data;
  }

  bool hasRecord(String collection, String id) {
    return _collections[collection]?.containsKey(id) ?? false;
  }

  Map<String, dynamic>? getRecordData(String collection, String id) {
    final data = _collections[collection]?[id];
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  void dispose() {
    _changesController.close();
  }
}
