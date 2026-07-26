import 'dart:typed_data';

abstract class CloudSyncProvider {
  Stream<void> get changes;
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