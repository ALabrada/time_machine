import 'dart:async';
import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

abstract class CloudBase implements CloudSyncProvider {
  static DateTime? _parseDate(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  CloudMetadata metadataFromData(String id, Map<String, dynamic> data) {
    final now = DateTime.now();
    final createdAt = _parseDate(data['createdAt']) ?? now;
    final updatedAt = _parseDate(data['updatedAt']) ?? createdAt;
    final deletedAt = _parseDate(data['deletedAt']);
    return CloudMetadata(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }

  @override
  bool get supportsFiles => false;

  Future<void> connect() async {}

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) => throw Exception('Not supported!');
  @override
  Future<Uint8List> downloadFile(String path) => throw Exception('Not supported!');
  @override
  Future<void> deleteFile(String path) => throw Exception('Not supported!');

  void dispose() {}
}

abstract class EventlessCloudBase extends CloudBase {
  @override
  bool get supportsEvents => false;

  @override
  Stream<CloudSyncEvent> get changes => Stream.empty(broadcast: true);
}

abstract class EventfulCloudBase extends CloudBase {
  final _streamController = StreamController<CloudSyncEvent>.broadcast();

  @override
  bool get supportsEvents => true;

  @override
  Stream<CloudSyncEvent> get changes => _streamController.stream;

  @override
  void dispose() {
    _streamController.close();
  }

  void publishEvent(CloudSyncEvent event) {
    _streamController.add(event);
  }
}