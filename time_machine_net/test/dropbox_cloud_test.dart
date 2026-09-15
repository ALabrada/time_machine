import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/dropbox_cloud.dart';
import 'package:time_machine_net/services/cloud/dropbox_token_store.dart';

import 'fakes/fake_dropbox_api.dart';

void main() {
  const clientId = 'test-client-id';
  late FakeDropboxApi adapter;
  late DropBoxCloud cloud;
  late _MemoryTokenStore store;

  setUp(() {
    adapter = FakeDropboxApi();
    store = _MemoryTokenStore()
      ..session = const DropboxSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
    cloud = DropBoxCloud(
      clientId: clientId,
      tokenStore: store,
      api: adapter,
      appRootFolderName: 'TimeMachine',
    );
  });

  group('initialize', () {
    test('returns dropbox id and creates the folder tree', () async {
      final cloudId = await cloud.initialize();

      expect(cloudId, 'dropbox/user@example.com');
      expect(adapter.folders, containsAll(<String>[
        '/Apps/TimeMachine',
        '/Apps/TimeMachine/models',
        '/Apps/TimeMachine/models/pictures',
        '/Apps/TimeMachine/models/records',
        '/Apps/TimeMachine/files',
      ]));
      expect(store.session!.accountEmail, 'user@example.com');
    });

    test('reuses folders from a previous session', () async {
      adapter.folders.addAll(const [
        '/Apps/TimeMachine',
        '/Apps/TimeMachine/models',
        '/Apps/TimeMachine/models/pictures',
        '/Apps/TimeMachine/models/records',
        '/Apps/TimeMachine/files',
      ]);

      final cloudId = await cloud.initialize();

      expect(cloudId, 'dropbox/user@example.com');
    });

    test('throws when the token store has no session', () async {
      store.session = null;

      expect(cloud.initialize(), throwsException);
    });
  });

  group('records', () {
    setUp(() async {
      await cloud.initialize();
    });

    test('saveRecord round-trips through getRecord and listRecords', () async {
      final metadata = await cloud.saveRecord('pictures', null, {
        'id': 'src-1',
        'name': 'Found',
        'nested': {'a': [1, 2]},
      });

      expect(metadata.deletedAt, isNull);
      expect(
        await cloud.getRecord('pictures', metadata.id),
        {'id': 'src-1', 'name': 'Found', 'nested': {'a': [1, 2]}},
      );
      final listed = await cloud.listRecords('pictures');
      expect(listed.single.id, metadata.id);
    });

    test('models are stored under folders for their collection', () async {
      final metadata = await cloud.saveRecord('records', null, {'id': 'src-r'});

      expect(adapter.files.keys.single,
          '/Apps/TimeMachine/models/records/${metadata.id}');
    });

    test('re-saving an id overwrites the same dropbox file', () async {
      final existing = await cloud.saveRecord('records', null, {'v': 1});

      await cloud.saveRecord('records', existing, {'v': 2});

      expect(adapter.files.keys.single,
          '/Apps/TimeMachine/models/records/${existing.id}');
      expect(await cloud.getRecord('records', existing.id), {'v': 2});
    });

    test('deleteRecord removes the dropbox file', () async {
      final metadata = await cloud.saveRecord('pictures', null, {'id': 'd'});

      await cloud.deleteRecord('pictures', metadata.id);

      expect(
        cloud.getRecord('pictures', metadata.id),
        throwsException,
      );
    });

    test('listRecords ignores since because dropbox cannot align server dates',
        () async {
      final old = await cloud.saveRecord(
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
        since: DateTime(2050, 1, 1),
      );

      expect(results.map((e) => e.id).toSet(), {old.id, fresh.id});
    });
  });

  group('files', () {
    setUp(() async {
      await cloud.initialize();
    });

    final bytes = Uint8List.fromList([10, 20, 30, 255]);

    test('uploadFile and downloadFile round-trip', () async {
      final path = await cloud.uploadFile(
        name: 'img.jpg',
        fileData: bytes,
        mimeType: 'image/jpeg',
      );

      expect(path, 'files/img.jpg');
      expect(await cloud.downloadFile(path), bytes);
    });

    test('nested file names create intermediate folders', () async {
      await cloud.uploadFile(
        name: 'photos/2024/img.jpg',
        fileData: bytes,
        mimeType: 'image/jpeg',
      );

      expect(adapter.files.keys.single,
          '/Apps/TimeMachine/files/photos/2024/img.jpg');
      expect(
        await cloud.downloadFile('files/photos/2024/img.jpg'),
        bytes,
      );
    });

    test('re-upload overwrites the existing file', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);
      await cloud.uploadFile(
        name: 'img.jpg',
        fileData: Uint8List.fromList([9]),
      );

      expect(adapter.files.keys.length, 1);
      expect(
        await cloud.downloadFile('files/img.jpg'),
        Uint8List.fromList([9]),
      );
    });

    test('deleteFile removes the dropbox file', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);

      await cloud.deleteFile('files/img.jpg');

      expect(cloud.downloadFile('files/img.jpg'), throwsException);
      expect(adapter.files, isEmpty);
    });

    test('onPull throws for a missing file', () async {
      expect(cloud.onPull('files/missing.jpg'), throwsException);
    });
  });

  group('changes', () {
    setUp(() async {
      await cloud.initialize();
    });

    test('publishes an insert event for a new record file', () async {
      final metadata = await cloud.saveRecord('records', null, {'v': 1});

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudInsertedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, metadata.id);
    });

    test('insert event carries no stale metadata before download', () async {
      final createdAt = DateTime(2024, 1, 1, 10);
      final updatedAt = DateTime(2024, 2, 2, 12);
      await cloud.saveRecord(
        'records',
        CloudMetadata(
          id: 'meta-carry',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
        {'v': 1},
      );

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      // Dropbox stores no custom properties; the event only carries the
      // identity of the changed record until its body is downloaded.
      expect(events.first.metadata.id, 'meta-carry');
    });

    test('does not publish events when nothing changed', () async {
      await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, isEmpty);
    });

    test('publishes an update event when a record changes remotely', () async {
      final first = await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      final path = '/Apps/TimeMachine/models/records/${first.id}';
      adapter.files[path] = _encodeBody({'v': 2}, id: first.id);
      adapter.touch(path);

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudUpdatedEvent');
      expect(events.first.metadata.id, first.id);
    });

    test('publishes a delete event when a record is removed remotely',
        () async {
      final first = await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      await adapter.delete('/Apps/TimeMachine/models/records/${first.id}');

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudDeletedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, first.id);
    });
  });

  group('credentials', () {
    test('logout clears the saved session and rejects further calls',
        () async {
      await cloud.initialize();

      await cloud.logout();

      expect(store.session, isNull);
      expect(
        cloud.onPush(
          path: 'files/a.jpg',
          fileData: Uint8List.fromList([1]),
        ),
        throwsException,
      );
      expect(cloud.initialize(), throwsException);
    });

    test('releases the API connection on logout and restores it on initialize',
        () async {
      await cloud.initialize();
      await cloud.logout();
      store.session = const DropboxSession(
        accessToken: 'access-token-2',
        refreshToken: 'refresh-token-2',
      );

      final cloudId = await cloud.initialize();

      // The same instance serves requests again through the restored API.
      expect(cloudId, 'dropbox/user@example.com');
      final metadata = await cloud.saveRecord('records', null, {'v': 1});
      expect(await cloud.getRecord('records', metadata.id), {'v': 1});
    });
  });
}

Uint8List _encodeBody(Map<String, dynamic> data, {String id = 'remote'}) {
  final model = {
    'data': data,
    'metadata': CloudMetadata(
      id: id,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    ).toJson(),
  };
  return Uint8List.fromList(zlib.encode(utf8.encode(jsonEncode(model))));
}

class _MemoryTokenStore implements DropboxTokenStore {
  DropboxSession? session;

  @override
  Future<DropboxSession?> read() async => session;

  @override
  Future<void> write(DropboxSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Subscribes to [cloud]'s change stream, runs [trigger], then collects every
/// event that was delivered while the subscription was active.
Future<List<dynamic>> _collectEvents(
  DropBoxCloud cloud,
  Future<void> Function() trigger,
) async {
  final events = <dynamic>[];
  final sub = cloud.changes.listen(events.add);
  await trigger();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return events;
}
