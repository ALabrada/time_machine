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
    return [
      await for(final item in onList(dirPath))
        CloudMetadata.fromJson((await _load(p.join(dirPath, item)))[metadataKey]),
    ];
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
    await onPush(path: path, fileData: binaryData, mimeType: 'application/zlib');
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

  Stream<String> onList(String path);

  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
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