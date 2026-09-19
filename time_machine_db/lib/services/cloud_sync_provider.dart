import 'dart:typed_data';

import 'package:time_machine_db/domain/cloud_metadata.dart';

abstract class CloudSyncProvider {
  Future<String> initialize();
  Stream<CloudSyncEvent> get changes;
  bool get supportsEvents;
  bool get supportsFiles;
  Map<Type, String> get collectionNames;

  Future<CloudMetadata> saveRecord(String collection, CloudMetadata? metadata, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getRecord(String collection, String id);
  Future<List<CloudMetadata>> listRecords(String collection, {DateTime? since});
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
  final CloudMetadata metadata;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudInsertedEvent({required this.metadata, required this.collection, this.data});
}

class CloudUpdatedEvent implements CloudSyncEvent {
  final CloudMetadata metadata;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudUpdatedEvent({required this.metadata, required this.collection, this.data});
}

class CloudDeletedEvent implements CloudSyncEvent {
  final CloudMetadata metadata;
  final String collection;
  final Map<String, dynamic>? data;
  const CloudDeletedEvent({required this.metadata, required this.collection, this.data});
}