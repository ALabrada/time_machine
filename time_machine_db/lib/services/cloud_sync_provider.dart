import 'dart:typed_data';

abstract class CloudSyncProvider {
  Stream<CloudSyncEvent> get changes;
  bool get supportsEvents;
  bool get supportsFiles;
  Map<Type, String> get collectionNames;

  Future<String> saveRecord(String collection, String? id, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getRecord(String collection, String id);
  Future<List<Map<String, dynamic>>> listRecords(String collection, {DateTime? since});
  Future<void> deleteRecord(String collection, String id);

  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  });
  Future<Uint8List> downloadFile(String path);
  Future<void> deleteFile(String path);
}

abstract class CloudSyncEvent {}

class CloudReconnectedEvent implements CloudSyncEvent {
  const CloudReconnectedEvent();
}

class UnknownEvent implements CloudSyncEvent {
  const UnknownEvent();
}

class CloudInsertedEvent implements CloudSyncEvent {
  final String id;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudInsertedEvent({required this.id, required this.collection, this.data});
}

class CloudUpdatedEvent implements CloudSyncEvent {
  final String id;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudUpdatedEvent({required this.id, required this.collection, this.data});
}

class CloudDeletedEvent implements CloudSyncEvent {
  final String id;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudDeletedEvent({required this.id, required this.collection, this.data});
}