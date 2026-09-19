import 'dart:async';
import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

abstract class CloudBase implements CloudSyncProvider {
  @override
  bool get supportsFiles => false;

  Future<void> logout() async {}

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) =>
      throw Exception('Not supported!');
  @override
  Future<Uint8List> downloadFile(String path) =>
      throw Exception('Not supported!');
  @override
  Future<void> deleteFile(String path) => throw Exception('Not supported!');

  void dispose() {}
}

mixin EventlessCloud on CloudBase {
  @override
  bool get supportsEvents => false;

  @override
  Stream<CloudSyncEvent> get changes => Stream.empty(broadcast: true);
}

mixin EventfulCloud on CloudBase {
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
