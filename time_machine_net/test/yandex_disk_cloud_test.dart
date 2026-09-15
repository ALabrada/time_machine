import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_auth.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_cloud.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_token_store.dart';

import 'fakes/fake_yandex_transport.dart';

void main() {
  const clientId = 'test-client-id';
  late FakeYandexTransport adapter;
  late YandexDiskCloud cloud;
  late _MemoryTokenStore store;

  setUp(() {
    adapter = FakeYandexTransport();
    store = _MemoryTokenStore()
      ..session = const YandexDiskSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
    cloud = YandexDiskCloud(
      clientId: clientId,
      tokenStore: store,
      transport: adapter,
    );
  });

  group('initialize', () {
    test('returns yandex id and creates the folder tree', () async {
      final cloudId = await cloud.initialize();

      expect(cloudId, 'yandex/user@example.com');
      expect(adapter.folders, containsAll(<String>[
        'app:',
        'app:/models',
        'app:/models/pictures',
        'app:/models/records',
        'app:/files',
      ]));
      expect(store.session!.userEmail, 'user@example.com');
    });

    test('reuses folders from a previous session', () async {
      adapter.folders.addAll(const [
        'app:',
        'app:/models',
        'app:/models/pictures',
        'app:/models/records',
        'app:/files',
      ]);

      final cloudId = await cloud.initialize();

      expect(cloudId, 'yandex/user@example.com');
    });

    test('throws when the token store has no session', () async {
      store.session = null;

      expect(cloud.initialize(), throwsException);
    });

    test('refreshes an expired access token before connecting', () async {
      store.session = YandexDiskSession(
        accessToken: 'expired-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      cloud = YandexDiskCloud(
        clientId: clientId,
        tokenStore: store,
        transport: adapter,
        auth: _FakeYandexAuth(),
      );

      final cloudId = await cloud.initialize();

      expect(cloudId, 'yandex/user@example.com');
      expect(store.session!.accessToken, 'fresh-token');
      expect(store.session!.refreshToken, 'fresh-refresh');
      expect(store.session!.expiresAt, isNotNull);
    });
  });

  group('authenticate', () {
    test('runs the consent flow through the browser and persists the session',
        () async {
      final opens = <Uri>[];
      final redirects = StreamController<Uri>.broadcast();

      cloud = YandexDiskCloud(
        clientId: clientId,
        tokenStore: store,
        transport: adapter,
        auth: _FakeYandexAuth(),
        redirectStream: redirects.stream,
        openBrowser: (uri) {
          opens.add(uri);
          // Simulate the browser returning the redirect immediately.
          redirects.add(Uri.parse('com.fakegem.historylens.yandex:/oauth2redirect'
              '?code=auth-code&state=state-123'));
        },
      );

      await cloud.authenticate();

      expect(opens, hasLength(1));
      expect(store.session, isNotNull);
      expect(store.session!.accessToken, 'auth-token');
      await redirects.close();
    });

    test('throws when no redirect stream is provided', () async {
      cloud = YandexDiskCloud(
        clientId: clientId,
        tokenStore: store,
        transport: adapter,
      );

      expect(cloud.authenticate(), throwsStateError);
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
          'app:/models/records/${metadata.id}');
    });

    test('re-saving an id overwrites the same yandex file', () async {
      final existing = await cloud.saveRecord('records', null, {'v': 1});

      await cloud.saveRecord('records', existing, {'v': 2});

      expect(adapter.files.keys.single,
          'app:/models/records/${existing.id}');
      expect(await cloud.getRecord('records', existing.id), {'v': 2});
    });

    test('deleteRecord removes the yandex file', () async {
      final metadata = await cloud.saveRecord('pictures', null, {'id': 'd'});

      await cloud.deleteRecord('pictures', metadata.id);

      expect(
        cloud.getRecord('pictures', metadata.id),
        throwsException,
      );
    });

    test('listRecords ignores since because yandex cannot align server dates',
        () async {
      final old = await cloud.saveRecord(
        'records',
        CloudMetadata(id: 'old-id', createdAt: DateTime(2020), updatedAt: DateTime(2020)),
        {'v': 1},
      );

      final fields = await cloud.listRecords('records', since: DateTime(2024));

      expect(fields.single.id, old.id);
    });
  });

  group('files', () {
    setUp(() async {
      await cloud.initialize();
    });

    final bytes = Uint8List.fromList([9]);

    test('uploadFile stores below the files folder', () async {
      final path = await cloud.uploadFile(name: 'img.jpg', fileData: bytes);

      expect(path, 'files/img.jpg');
      expect(adapter.files.keys.single, 'app:/files/img.jpg');
    });

    test('downloadFile reads back the uploaded bytes', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);

      expect(adapter.files.keys.length, 1);
      expect(
        await cloud.downloadFile('files/img.jpg'),
        Uint8List.fromList([9]),
      );
    });

    test('deleteFile removes the yandex file', () async {
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

      // Yandex stores no custom properties; the event only carries the
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

      final path = 'app:/models/records/${first.id}';
      adapter.files[path] = _encodeBody({'v': 2}, id: first.id);
      adapter.touch(path);

      final events =
          await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudUpdatedEvent');
      expect(events.first.metadata.id, first.id);
    });

    test('fallback fingerprint detects a change without an etag', () async {
      adapter.emitEtags = false;
      final first = await cloud.saveRecord('records', null, {'v': 1});
      await cloud.pollChanges();

      // With no etag the revision is `size + mtime`; growing the body changes
      // the size and must surface as an update.
      final path = 'app:/models/records/${first.id}';
      adapter.files[path] = _encodeBody(
        {'v': 2, 'note': 'a longer payload changes the file size'},
        id: first.id,
      );
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

      await adapter.remove('app:/models/records/${first.id}');

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

    test('releases the transport on logout and restores it on initialize',
        () async {
      await cloud.initialize();
      await cloud.logout();
      store.session = const YandexDiskSession(
        accessToken: 'access-token-2',
        refreshToken: 'refresh-token-2',
      );

      final cloudId = await cloud.initialize();

      // The same instance serves requests again through the restored transport.
      expect(cloudId, 'yandex/user@example.com');
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

class _MemoryTokenStore implements YandexDiskTokenStore {
  YandexDiskSession? session;

  @override
  Future<YandexDiskSession?> read() async => session;

  @override
  Future<void> write(YandexDiskSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// OAuth double that returns a fresh session without launching a browser,
/// for the expired-token refresh path.
class _FakeYandexAuth extends YandexDiskAuth {
  @override
  Future<YandexDiskSession?> refresh(
    String refreshToken, {
    required String clientId,
    http.Client? httpClient,
  }) async {
    return YandexDiskSession(
      accessToken: 'fresh-token',
      refreshToken: 'fresh-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<YandexDiskSession> obtainSession({
    required String clientId,
    required void Function(Uri authorizationUri) openBrowser,
    required Stream<Uri> redirectStream,
    List<String> scopes = const [],
    http.Client? httpClient,
  }) async {
    // Simulate the browser opening and returning via the redirect stream.
    final completer = Completer<void>();
    final sub = redirectStream.listen((uri) {
      if (!completer.isCompleted && uri.queryParameters['state'] != null) {
        completer.complete();
      }
    });
    openBrowser(Uri.parse('https://oauth.yandex.ru/authorize?state=state-123'));
    await completer.future.timeout(const Duration(seconds: 1));
    await sub.cancel();
    return const YandexDiskSession(
      accessToken: 'auth-token',
      refreshToken: 'auth-refresh',
    );
  }
}

/// Subscribes to [cloud]'s change stream, runs [trigger], then collects every
/// event that was delivered while the subscription was active.
Future<List<dynamic>> _collectEvents(
  YandexDiskCloud cloud,
  Future<void> Function() trigger,
) async {
  final events = <dynamic>[];
  final sub = cloud.changes.listen(events.add);
  await trigger();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return events;
}