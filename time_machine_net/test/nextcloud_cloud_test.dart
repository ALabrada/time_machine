import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/webdav.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/nextcloud_cloud.dart';
import 'package:time_machine_net/services/cloud/nextcloud_token_store.dart';

import 'fakes/fake_nextcloud_server.dart';

void main() {
  late FakeNextcloudServer server;
  late NextCloudCloud cloud;
  late _MemoryTokenStore store;

  NextcloudClient buildClient() => NextcloudClient(
        Uri.parse('http://localhost:8080/nextcloud'),
        loginName: 'user',
        appPassword: 'app-password',
        httpClient: server,
      );

  setUp(() {
    server = FakeNextcloudServer();
    store = _MemoryTokenStore()
      ..session = const NextcloudSession(
        serverUrl: 'http://localhost:8080/nextcloud',
        loginName: 'user',
        password: 'app-password',
      );
    cloud = NextCloudCloud(
      tokenStore: store,
      client: buildClient(),
      appRootFolderName: 'TimeMachine',
    );
  });

  group('initialize', () {
    test('returns nextcloud id and creates the folder tree', () async {
      final cloudId = await cloud.initialize();

      expect(cloudId, 'http://localhost:8080/nextcloud/user');
      expect(
          server.folders,
          containsAll(<String>[
            'TimeMachine',
            'TimeMachine/models',
            'TimeMachine/models/pictures',
            'TimeMachine/models/records',
            'TimeMachine/files',
          ]));
    });

    test('reuses folders from a previous session', () async {
      server.folders.addAll(const [
        'TimeMachine',
        'TimeMachine/models',
        'TimeMachine/models/pictures',
        'TimeMachine/models/records',
        'TimeMachine/files',
      ]);

      final cloudId = await cloud.initialize();

      expect(cloudId, 'http://localhost:8080/nextcloud/user');
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
        'nested': {
          'a': [1, 2]
        },
      });

      expect(metadata.deletedAt, isNull);
      expect(
        await cloud.getRecord('pictures', metadata.id),
        {
          'id': 'src-1',
          'name': 'Found',
          'nested': {
            'a': [1, 2]
          }
        },
      );
      final listed = await cloud.listRecords('pictures');
      expect(listed.single.id, metadata.id);
    });

    test('models are stored under folders for their collection', () async {
      final metadata = await cloud.saveRecord('records', null, {'id': 'src-r'});

      expect(server.files.keys.single,
          'TimeMachine/models/records/${metadata.id}');
    });

    test('re-saving an id overwrites the same nextcloud file', () async {
      final existing = await cloud.saveRecord('records', null, {'v': 1});

      await cloud.saveRecord('records', existing, {'v': 2});

      expect(server.files.keys.single,
          'TimeMachine/models/records/${existing.id}');
      expect(await cloud.getRecord('records', existing.id), {'v': 2});
    });

    test('deleteRecord removes the nextcloud file', () async {
      final metadata = await cloud.saveRecord('pictures', null, {'id': 'd'});

      await cloud.deleteRecord('pictures', metadata.id);

      expect(
        cloud.getRecord('pictures', metadata.id),
        throwsException,
      );
    });

    test('onPush sets server dates from the CloudMetadata', () async {
      final metadata = await cloud.saveRecord(
        'pictures',
        CloudMetadata(
          id: 'dated',
          createdAt: DateTime.utc(2024, 1, 1),
          updatedAt: DateTime.utc(2024, 2, 2),
        ),
        {'id': 'src-dated'},
      );

      final path = 'TimeMachine/models/pictures/${metadata.id}';
      expect(server.lastModifiedTimes[path], DateTime.utc(2024, 2, 2));
      expect(server.createdTimes[path], DateTime.utc(2024, 1, 1));
    });

    test('listRecords respects since and skips untouched files', () async {
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

      final oldResults = await cloud.listRecords(
        'pictures',
        since: DateTime(2024, 1, 15),
      );
      expect(oldResults.single.id, fresh.id);

      expect(
        await cloud.listRecords('pictures', since: DateTime(2050, 1, 1)),
        isEmpty,
      );
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

      expect(server.files.keys.single, 'TimeMachine/files/photos/2024/img.jpg');
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

      expect(server.files.keys.length, 1);
      expect(
        await cloud.downloadFile('files/img.jpg'),
        Uint8List.fromList([9]),
      );
    });

    test('deleteFile removes the nextcloud file', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);

      await cloud.deleteFile('files/img.jpg');

      expect(cloud.downloadFile('files/img.jpg'), throwsException);
      expect(server.files, isEmpty);
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

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudInsertedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, metadata.id);
    });

    test('does not publish events when nothing changed', () async {
      await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, isEmpty);
    });

    test('publishes an update event when a record changes remotely', () async {
      final first = await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      final path = 'TimeMachine/models/records/${first.id}';
      server.addFile(path, _encodeBody({'v': 2}, id: first.id));

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudUpdatedEvent');
      expect(events.first.metadata.id, first.id);
    });

    test('publishes a delete event when a record is removed remotely',
        () async {
      final first = await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      server.removePath('TimeMachine/models/records/${first.id}');

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudDeletedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, first.id);
    });
  });

  group('credentials', () {
    test('logout clears the saved session and rejects further calls', () async {
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

    test('releases the connection on logout and restores it on initialize',
        () async {
      await cloud.initialize();
      await cloud.logout();
      store.session = const NextcloudSession(
        serverUrl: 'http://localhost:8080/nextcloud',
        loginName: 'user',
        password: 'app-password-2',
      );

      final cloudId = await cloud.initialize();

      expect(cloudId, 'http://localhost:8080/nextcloud/user');
      final metadata = await cloud.saveRecord('records', null, {'v': 1});
      expect(await cloud.getRecord('records', metadata.id), {'v': 1});
    });
  });

  group('authentication', () {
    test('authenticate persists the submitted credentials', () async {
      await cloud.authenticate(
        serverUrl: 'http://localhost:8080/nextcloud',
        loginName: 'user',
        password: 'app-password',
      );

      expect(store.session?.serverUrl, 'http://localhost:8080/nextcloud');
      expect(store.session?.loginName, 'user');
      expect(store.session?.password, 'app-password');
    });

    test(
        'logout clears a fresh session that was never validated but keeps '
        'the remembered credentials', () async {
      await cloud.authenticate(
        serverUrl: 'http://localhost:8080/nextcloud',
        loginName: 'user',
        password: 'app-password',
      );

      await cloud.logout();

      expect(store.session, isNull);
      expect(cloud.serverUrl, 'http://localhost:8080/nextcloud');
      expect(cloud.userEmail, 'user');
      expect(cloud.initialize(), throwsException);
    });

    test('logout clears a session confirmed by initialize', () async {
      await cloud.initialize();

      await cloud.logout();

      expect(store.session, isNull);
    });
  });

  group('app-password → account-password fallback', () {
    test('retries with HTTP Basic when the Bearer token is rejected', () async {
      server
        ..appPassword = 'valid-app-password'
        ..accountPassword = 'account-password';
      final wrapper = NextcloudAuthFallbackClient(
        inner: server,
        loginName: 'user',
        password: 'account-password',
      );
      final client = NextcloudClient(
        Uri.parse('http://localhost:8080/nextcloud'),
        loginName: 'user',
        appPassword: 'rejected-bearer-token',
        httpClient: wrapper,
      );

      final result = await client.webdav.propfind(
        PathUri.parse('TimeMachine'),
        depth: WebDavDepth.zero,
      );

      expect(result, isNotNull);
      expect(server.requestedAuthorizations, hasLength(2));
      expect(
          server.requestedAuthorizations.first, 'Bearer rejected-bearer-token');
      expect(server.requestedAuthorizations.last, startsWith('Basic '));
    });

    test('fails when both the Bearer token and Basic credentials are rejected',
        () async {
      server
        ..appPassword = 'valid-app-password'
        ..accountPassword = 'account-password';
      final wrapper = NextcloudAuthFallbackClient(
        inner: server,
        loginName: 'user',
        password: 'wrong-account-password',
      );
      final client = NextcloudClient(
        Uri.parse('http://localhost:8080/nextcloud'),
        loginName: 'user',
        appPassword: 'rejected-bearer-token',
        httpClient: wrapper,
      );

      await expectLater(
        client.webdav.propfind(
          PathUri.parse('TimeMachine'),
          depth: WebDavDepth.zero,
        ),
        throwsA(isA<DynamiteStatusCodeException>()),
      );
    });

    test('retried PUT re-sends the original body', () async {
      server
        ..appPassword = 'valid-app-password'
        ..accountPassword = 'account-password';
      final wrapper = NextcloudAuthFallbackClient(
        inner: server,
        loginName: 'user',
        password: 'account-password',
      );
      final client = NextcloudClient(
        Uri.parse('http://localhost:8080/nextcloud'),
        loginName: 'user',
        appPassword: 'rejected-bearer-token',
        httpClient: wrapper,
      );

      final bytes = Uint8List.fromList(utf8.encode('content-body'));
      await client.webdav.put(
        bytes,
        PathUri.parse('TimeMachine/file.txt'),
      );

      expect(server.files['TimeMachine/file.txt'], bytes);
      expect(server.requestedAuthorizations, hasLength(2));
      expect(
          server.requestedAuthorizations.first, 'Bearer rejected-bearer-token');
      expect(server.requestedAuthorizations.last, startsWith('Basic '));
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

class _MemoryTokenStore implements NextcloudTokenStore {
  NextcloudSession? session;

  @override
  Future<NextcloudSession?> read() async => session;

  @override
  Future<void> write(NextcloudSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Subscribes to [cloud]'s change stream, runs [trigger], then collects every
/// event that was delivered while the subscription was active.
Future<List<dynamic>> _collectEvents(
  NextCloudCloud cloud,
  Future<void> Function() trigger,
) async {
  final events = <dynamic>[];
  final sub = cloud.changes.listen(events.add);
  await trigger();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return events;
}
