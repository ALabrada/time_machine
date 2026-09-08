import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/cloud_base.dart';
import 'package:time_machine_net/services/cloud/file_cloud_base.dart';

class InMemoryFileCloud extends FileCloudBase with EventlessCloud {
  InMemoryFileCloud({super.encryptionKey});

  final Map<String, Uint8List> store = {};
  final Map<String, String?> storeMetadata = {};
  final Map<String, DateTime> storeUpdates = {};
  final List<String> pushedPaths = [];
  final List<String> deletedPaths = [];
  final List<String?> pushedMimeTypes = [];

  @override
  Future<String> initialize() async => 'test-cloud';

  @override
  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
    String? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    pushedPaths.add(path);
    pushedMimeTypes.add(mimeType);
    store[path] = fileData;
    storeMetadata[path] = metadata;
    storeUpdates[path] = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Future<String> onDelete(String path) async {
    deletedPaths.add(path);
    store.remove(path);
    storeMetadata.remove(path);
    storeUpdates.remove(path);
    return path;
  }

  @override
  Future<Uint8List> onPull(String path) async {
    final data = store[path];
    if (data == null) {
      throw Exception('Not found: $path');
    }
    return data;
  }

  @override
  Stream<CloudFileEntry> onList(String path, {DateTime? since}) async* {
    final prefix = path.endsWith('/') ? path : '$path/';
    final names = store.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .where((name) => name.isNotEmpty && !name.contains('/'))
        .toList()
      ..sort();
    for (final name in names) {
      if (since != null) {
        final updated = storeUpdates['$prefix$name'];
        if (updated != null && since.isAfter(updated)) continue;
      }
      yield CloudFileEntry(name: name, metadata: storeMetadata['$prefix$name']);
    }
  }
}

void main() {
  late InMemoryFileCloud cloud;

  setUp(() {
    cloud = InMemoryFileCloud();
  });

  Map<String, dynamic> storedModel(String path) {
    return json.decode(utf8.decode(zlib.decode(cloud.store[path]!)))
        as Map<String, dynamic>;
  }

  group('FileCloudBase basics', () {
    test('supportsFiles returns true', () {
      expect(cloud.supportsFiles, isTrue);
    });

    test('collectionNames returns expected mapping', () {
      expect(cloud.collectionNames[Picture], 'pictures');
      expect(cloud.collectionNames[Record], 'records');
      expect(cloud.collectionNames.length, 2);
    });

    test('inherits supportsEvents false from EventlessCloud', () {
      expect(cloud.supportsEvents, isFalse);
      expect(cloud.changes, isA<Stream<CloudSyncEvent>>());
    });
  });

  group('saveRecord', () {
    test('insert stores model with generated id and fresh timestamps', () async {
      final metadata = await cloud.saveRecord('records', null, {
        'id': 'src-1',
        'name': 'Test',
      });

      expect(metadata.id, isNotEmpty);
      expect(metadata.deletedAt, isNull);
      expect(cloud.pushedMimeTypes.single, 'application/zlib');

      final path = 'models/records/${Uri.encodeComponent(metadata.id)}';
      expect(cloud.store.containsKey(path), isTrue);
      expect(cloud.pushedPaths.single, path);

      final model = storedModel(path);
      expect(model, {
        FileCloudBase.dataKey: {'id': 'src-1', 'name': 'Test'},
        FileCloudBase.metadataKey: metadata.toJson(),
      });
      final stored = CloudMetadata.fromJson(
        json.decode(cloud.storeMetadata[path]!) as Map<String, dynamic>,
      );
      expect(stored.id, metadata.id);
      expect(stored.createdAt, metadata.createdAt);
      expect(stored.updatedAt, metadata.updatedAt);
      expect(stored.deletedAt, isNull);
    });

    test('model is stored deflate-compressed, not raw text', () async {
      final metadata = await cloud.saveRecord('records', null, {
        'id': 'src-1',
        'name': 'Test',
      });
      final raw = cloud.store.entries.single.value;

      final plainText = utf8.encode(json.encode({
        FileCloudBase.dataKey: {'id': 'src-1', 'name': 'Test'},
        FileCloudBase.metadataKey: metadata.toJson(),
      }));
      expect(raw, isNot(equals(plainText)));

      final decoded = json.decode(utf8.decode(zlib.decode(raw)))
          as Map<String, dynamic>;
      expect(decoded, {
        FileCloudBase.dataKey: {'id': 'src-1', 'name': 'Test'},
        FileCloudBase.metadataKey: metadata.toJson(),
      });
    });

    test('update preserves provided metadata and id', () async {
      final createdAt = DateTime(2024, 1, 1);
      final deletedAt = DateTime(2024, 2, 1);

      final metadata = await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: 'my-existing-id',
          createdAt: createdAt,
          updatedAt: createdAt,
          deletedAt: deletedAt,
        ),
        {'id': 'src-2', 'name': 'Updated'},
      );

      expect(metadata.id, 'my-existing-id');
      expect(metadata.createdAt, createdAt);
      expect(metadata.updatedAt, createdAt);
      expect(metadata.deletedAt, deletedAt);
    });

    test('provided metadata is persisted and survives a listRecords round trip',
        () async {
      final createdAt = DateTime(2024, 1, 1);
      await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: 'round-trip',
          createdAt: createdAt,
          updatedAt: DateTime(2024, 2, 2),
        ),
        {'name': 'v1'},
      );

      final reloaded = (await cloud.listRecords('records')).single;
      expect(reloaded.id, 'round-trip');
      expect(reloaded.createdAt, createdAt);
      expect(reloaded.updatedAt, DateTime(2024, 2, 2));
      expect(reloaded.deletedAt, isNull);
    });

    test('dates are serialized as epoch milliseconds, not strings', () async {
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 2, 2);
      await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: 'epoch-meta',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
        {'id': 'src-epoch'},
      );

      final model = storedModel('models/records/epoch-meta');
      final serialized =
          model[FileCloudBase.metadataKey] as Map<String, dynamic>;
      expect(serialized['createdAt'], createdAt.millisecondsSinceEpoch);
      expect(serialized['updatedAt'], updatedAt.millisecondsSinceEpoch);
      expect(serialized['deletedAt'], isNull);

      final reloaded = (await cloud.listRecords('records')).single;
      expect(reloaded.id, 'epoch-meta');
      expect(reloaded.createdAt, createdAt);
      expect(reloaded.updatedAt, updatedAt);
    });

    test('record id is url-encoded in the storage path', () async {
      const id = 'a/b c?d';

      final metadata = await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: id,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
        {'v': 1},
      );

      expect(metadata.id, id);
      final path = 'models/records/${Uri.encodeComponent(id)}';
      expect(cloud.store.containsKey(path), isTrue);

      final data = await cloud.getRecord('records', id);
      expect(data, {'v': 1});

      await cloud.deleteRecord('records', id);
      expect(cloud.store.containsKey(path), isFalse);
    });
  });

  group('getRecord', () {
    test('returns data stored by saveRecord', () async {
      final metadata = await cloud.saveRecord('pictures', null, {
        'id': 'src-3',
        'name': 'Found',
        'nested': {'a': [1, 2]},
      });

      final data = await cloud.getRecord('pictures', metadata.id);

      expect(data, {
        'id': 'src-3',
        'name': 'Found',
        'nested': {'a': [1, 2]},
      });
    });

    test('returns null when the model has no data key', () async {
      await cloud.onPush(
        path: 'models/records/data-less',
        fileData: Uint8List.fromList(
          zlib.encode(utf8.encode(json.encode({}))),
        ),
        mimeType: 'application/zlib',
      );

      final data = await cloud.getRecord('records', 'data-less');
      expect(data, isNull);
    });
  });

  group('listRecords', () {
    Future<CloudMetadata> seed(String id, DateTime updatedAt) async {
      return await cloud.saveRecord(
        'pictures',
        CloudMetadata(
          id: id,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: updatedAt,
        ),
        {'id': 'src-$id'},
      );
    }

    test('returns metadata for every stored record', () async {
      final m1 = await seed('a', DateTime(2024, 1, 2, 1));
      final m2 = await seed('b', DateTime(2024, 1, 3, 2));

      final results = await cloud.listRecords('pictures');

      expect(results.length, 2);
      expect(results[0].id, 'a');
      expect(results[0].createdAt, DateTime(2024, 1, 1));
      expect(results[0].updatedAt, m1.updatedAt);
      expect(results[0].deletedAt, isNull);
      expect(results[1].id, 'b');
      expect(results[1].updatedAt, m2.updatedAt);
    });

    test('does not leak records from other collections', () async {
      await seed('a', DateTime(2024, 1, 2));
      await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: 'r1',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
        {'id': 'src-r1'},
      );

      final results = await cloud.listRecords('pictures');

      expect(results.length, 1);
      expect(results.single.id, 'a');
    });

    test('falls back to the metadata embedded in the file data when the '
        'custom metadata field is absent', () async {
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 2, 2, 3);
      await cloud.onPush(
        path: 'models/pictures/legacy',
        fileData: Uint8List.fromList(
          zlib.encode(utf8.encode(json.encode({
            FileCloudBase.dataKey: {'id': 'src-legacy'},
            FileCloudBase.metadataKey: CloudMetadata(
              id: 'legacy',
              createdAt: createdAt,
              updatedAt: updatedAt,
            ).toJson(),
          }))),
        ),
        mimeType: 'application/zlib',
      );

      final results = await cloud.listRecords('pictures');

      expect(results, hasLength(1));
      expect(results.single.id, 'legacy');
      expect(results.single.createdAt, createdAt);
      expect(results.single.updatedAt, updatedAt);
      expect(results.single.deletedAt, isNull);
    });

    test('listRecords with since skips records updated before since', () async {
      await cloud.saveRecord(
        'pictures',
        CloudMetadata(
          id: 'old-rec',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
        {'id': 'src-old'},
      );
      final fresh = await cloud.saveRecord('pictures', null, {'id': 'src-new'});

      final results = await cloud.listRecords(
        'pictures',
        since: DateTime(2024, 6, 1),
      );

      expect(results.single.id, fresh.id);
      expect(
        await cloud.listRecords('pictures', since: DateTime(2050, 1, 1)),
        isEmpty,
      );
    });
  });

  group('deleteRecord', () {
    test('removes the record file from storage', () async {
      final metadata = await cloud.saveRecord('records', null, {'id': 'src-4'});
      final path = 'models/records/${Uri.encodeComponent(metadata.id)}';
      expect(cloud.store.containsKey(path), isTrue);

      await cloud.deleteRecord('records', metadata.id);

      expect(cloud.deletedPaths, [path]);
      expect(cloud.store.containsKey(path), isFalse);
    });
  });

  group('encryption', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('rejects keys of unsupported lengths', () {
      expect(() => InMemoryFileCloud(encryptionKey: Uint8List(8)),
          throwsArgumentError);
      expect(() => InMemoryFileCloud(encryptionKey: Uint8List(17)),
          throwsArgumentError);
      expect(() => InMemoryFileCloud(encryptionKey: Uint8List(64)),
          throwsArgumentError);
    });

    test('encrypted records round-trip through getRecord and listRecords',
        () async {
      final encrypted = InMemoryFileCloud(encryptionKey: key);

      final metadata = await encrypted.saveRecord('records', null, {
        'id': 'src-secret',
        'name': 'Secret',
      });
      final metadata2 = await encrypted.saveRecord('pictures', null, {
        'id': 'pic-secret',
      });

      expect(
        await encrypted.getRecord('records', metadata.id),
        {'id': 'src-secret', 'name': 'Secret'},
      );
      expect((await encrypted.listRecords('records')).map((e) => e.id),
          [metadata.id]);
      expect((await encrypted.listRecords('pictures')).map((e) => e.id),
          [metadata2.id]);
    });

    test('stored bytes are opaque (not a zlib stream)', () async {
      final encrypted = InMemoryFileCloud(encryptionKey: key);
      await encrypted.saveRecord('records', null, {'id': 'src-sec'});
      final raw = encrypted.store.entries.single.value;

      expect(raw.length, greaterThan(12));
      expect(() => zlib.decode(raw), throwsException);
    });

    test('re-save with same id produces different ciphertext', () async {
      final encrypted = InMemoryFileCloud(encryptionKey: key);
      final existing = CloudMetadata(
        id: 'same-id',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      await encrypted.saveRecord('records', existing, {'v': 1});
      final first = encrypted.store.entries.single.value;
      await encrypted.saveRecord('records', existing, {'v': 1});
      final second = encrypted.store.entries.single.value;

      expect(first, isNot(equals(second)));
    });

    test('encrypted records are not readable without the key', () async {
      final encrypted = InMemoryFileCloud(encryptionKey: key);
      final metadata = await encrypted.saveRecord('records', null, {'id': 'x'});
      final path = 'models/records/${Uri.encodeComponent(metadata.id)}';
      final raw = encrypted.store[path]!;

      final plain = InMemoryFileCloud();
      await plain.onPush(
        path: path,
        fileData: raw,
        mimeType: 'application/zlib',
      );

      expect(() => plain.getRecord('records', metadata.id), throwsException);
    });

    test('encrypted records are not readable with a different key', () async {
      final encrypted = InMemoryFileCloud(encryptionKey: key);
      final metadata = await encrypted.saveRecord('records', null, {'id': 'y'});
      final path = 'models/records/${Uri.encodeComponent(metadata.id)}';
      final raw = encrypted.store[path]!;

      final wrong = InMemoryFileCloud(
        encryptionKey: Uint8List.fromList(
          List<int>.generate(32, (i) => 255 - i),
        ),
      );
      await wrong.onPush(
        path: path,
        fileData: raw,
        mimeType: 'application/zlib',
      );

      expect(() => wrong.getRecord('records', metadata.id), throwsException);
    });
  });

  group('file operations', () {
    final fileBytes = Uint8List.fromList([10, 20, 30, 255]);

    test('uploadFile pushes to filesDir and preserves mime type', () async {
      final path = await cloud.uploadFile(
        name: 'photos/img.jpg',
        fileData: fileBytes,
        mimeType: 'image/jpeg',
      );

      expect(path, 'files/photos/img.jpg');
      expect(cloud.store[path], fileBytes);
      expect(cloud.pushedMimeTypes.single, 'image/jpeg');
    });

    test('uploadFile round-trips with downloadFile', () async {
      final path = await cloud.uploadFile(name: 'img.jpg', fileData: fileBytes);

      final data = await cloud.downloadFile(path);

      expect(data, fileBytes);
    });

    test('uploadFile accepts names and stores under filesDir', () async {
      final path = await cloud.uploadFile(
        name: '../secret',
        fileData: fileBytes,
      );

      expect(path, p.join(FileCloudBase.filesDir, '../secret'));
      expect(cloud.pushedPaths, isNotEmpty);
    });

    test('downloadFile returns stored bytes', () async {
      await cloud.uploadFile(name: 'a.jpg', fileData: fileBytes);

      expect(await cloud.downloadFile('files/a.jpg'), fileBytes);
    });

    test('downloadFile rejects paths outside filesDir', () async {
      expect(cloud.downloadFile('models/x'), throwsA('Invalid path'));
      expect(cloud.downloadFile('files/../x'), throwsA('Invalid path'));
      expect(cloud.downloadFile('x'), throwsA('Invalid path'));
    });

    test('downloadFile returns null-safe error for missing file', () async {
      expect(cloud.downloadFile('files/missing.jpg'), throwsException);
    });

    test('deleteFile removes the file and guards outside paths', () async {
      await cloud.uploadFile(name: 'b.jpg', fileData: fileBytes);

      await cloud.deleteFile('files/b.jpg');

      expect(cloud.deletedPaths, ['files/b.jpg']);
      expect(cloud.store.containsKey('files/b.jpg'), isFalse);
      expect(cloud.deleteFile('x'), throwsA('Invalid path'));
    });
  });
}