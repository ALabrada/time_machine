import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/cloud_base.dart';
import 'package:uuid/uuid.dart';

abstract class FileCloudBase extends CloudBase {
  FileCloudBase({Uint8List? encryptionKey})
      : _encryptionKey = encryptionKey {
    if (_encryptionKey != null &&
        !const {16, 24, 32}.contains(_encryptionKey.length)) {
      throw ArgumentError('encryptionKey must be 16, 24 or 32 bytes');
    }
  }

  static const dataKey = 'data';
  static const metadataKey = 'metadata';
  static const modelsDir = 'models';
  static const filesDir = 'files';
  static const _nonceLength = 12;

  final Uint8List? _encryptionKey;

  @override
  bool get supportsFiles => true;

  @override
  Map<Type, String> get collectionNames => const {
    Picture: 'pictures',
    Record: 'records',
  };

  @override
  Future<void> deleteRecord(String collection, String id) async {
    final path = p.join(modelsDir, collection, Uri.encodeComponent(id));
    await onDelete(path);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final path = p.join(modelsDir, collection, Uri.encodeComponent(id));
    final data = await _load(path);
    return data[dataKey];
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection) async {
    final dirPath = p.join(modelsDir, collection);
    final result = <CloudMetadata>[];
    await for (final entry in onList(dirPath)) {
      var metadataJson = entry.metadata;
      if (metadataJson == null) {
        final body = await _load(p.join(dirPath, entry.name));
        final stored = body[metadataKey];
        if (stored is Map<String, dynamic>) {
          metadataJson = jsonEncode(stored);
        }
      }
      if (metadataJson == null) continue;
      result.add(CloudMetadata.fromJson(jsonDecode(metadataJson)));
    }
    return result;
  }

  @override
  Future<CloudMetadata> saveRecord(String collection, CloudMetadata? metadata, Map<String, dynamic> data) async {
    final id = metadata?.id ?? Uuid().v4();
    final now = DateTime.now();
    final path = p.join(modelsDir, collection, Uri.encodeComponent(id));
    final actualMetadata = metadata ?? CloudMetadata(id: id, createdAt: now, updatedAt: now);
    final model = {
      dataKey: data,
      metadataKey: actualMetadata.toJson(),
    };
    final key = _encryptionKey;
    final binaryData = await Isolate.run(
      () => _encryptContent(
        Uint8List.fromList(zlib.encode(utf8.encode(jsonEncode(model)))),
        key,
      ),
    );
    await onPush(
      path: path,
      fileData: binaryData,
      mimeType: 'application/zlib',
      metadata: jsonEncode(actualMetadata.toJson()),
    );
    return actualMetadata;
  }

  Future<Map<String, dynamic>> _load(String path) async {
    final binaryData = await onPull(path);
    final key = _encryptionKey;
    return Isolate.run(
      () => jsonDecode(utf8.decode(zlib.decode(_decryptContent(binaryData, key)))),
    );
  }

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) async {
    final path = p.join(filesDir, name);
    await onPush(
      path: path,
      fileData: fileData,
      mimeType: mimeType,
    );
    return path;
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    if (!p.isWithin(filesDir, path)) {
      throw 'Invalid path';
    }
    return await onPull(path);
  }

  @override
  Future<void> deleteFile(String path) async {
    if (!p.isWithin(filesDir, path)) {
      throw 'Invalid path';
    }
    await onDelete(path);
  }

  Stream<CloudFileEntry> onList(String path);

  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
    String? metadata,
  });

  Future<String> onDelete(String path);

  Future<Uint8List> onPull(String path);

  static Uint8List _encryptContent(Uint8List data, Uint8List? key) {
    if (key == null) {
      return data;
    }
    final nonce = _randomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final cipherText = cipher.process(data);
    return Uint8List.fromList([...nonce, ...cipherText]);
  }

  static Uint8List _decryptContent(Uint8List data, Uint8List? key) {
    if (key == null) {
      return data;
    }
    final nonce = Uint8List.sublistView(data, 0, _nonceLength);
    final cipherText = data.sublist(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(cipherText);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

class CloudFileEntry {
  const CloudFileEntry({
    required this.name,
    this.metadata,
  });

  final String name;

  /// JSON-encoded [CloudMetadata], read from a custom metadata field of the
  /// stored file. `null` when the file carries no custom metadata (e.g. plain
  /// uploaded files).
  final String? metadata;
}

mixin EventfulFileCloud on FileCloudBase {
  final _streamController = StreamController<CloudSyncEvent>.broadcast();

  @override
  bool get supportsEvents => true;

  @override
  Stream<CloudSyncEvent> get changes => _streamController.stream;

  @override
  void dispose() {
    _streamController.close();
  }

  String? _findCollection(String path) {
    final dirPath = p.dirname(path);
    final collection = p.basename(dirPath);
    if (p.dirname(dirPath) != FileCloudBase.modelsDir || !collectionNames.values.contains(collection)) {
      return null;
    }
    return collection;
  }

  CloudMetadata _loadMetadata({required String path, String? metadata, bool deleted=false}) {
    final id = p.basename(path);
    final now = DateTime.now();
    if (metadata == null) {
      return CloudMetadata(id: id, createdAt: now, updatedAt: now, deletedAt: deleted ? now : null);
    }
    final result = CloudMetadata.fromJson(jsonDecode(metadata));
    return deleted ? result.copy(deletedAt: result.deletedAt ?? now) : result;
  }

  void publishFileDeleted({required String path, String? metadata}) {
    final collection = _findCollection(path);
    if (collection == null) {
      return;
    }
    final event = CloudDeletedEvent(
      metadata: _loadMetadata(path: path, metadata: metadata, deleted: true),
      collection: collection,
    );
    publishEvent(event);
  }

  void publishFileInserted({required String path, String? metadata}) {
    final collection = _findCollection(path);
    if (collection == null) {
      return;
    }
    final event = CloudInsertedEvent(
      metadata: _loadMetadata(path: path, metadata: metadata),
      collection: collection,
    );
    publishEvent(event);
  }

  void publishFileUpdated({required String path, String? metadata}) {
    final collection = _findCollection(path);
    if (collection == null) {
      return;
    }
    final event = CloudUpdatedEvent(
      metadata: _loadMetadata(path: path, metadata: metadata),
      collection: collection,
    );
    publishEvent(event);
  }

  void publishEvent(CloudSyncEvent event) {
    _streamController.add(event);
  }
}