import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_net/services/cloud/google_drive_cloud.dart';

import 'fakes/fake_drive_adapter.dart';

void main() {
  late FakeDriveAdapter adapter;
  late GoogleDriveCloud cloud;

  setUp(() {
    adapter = FakeDriveAdapter();
    cloud = GoogleDriveCloud(
      client: adapter.client(),
      accessToken: 'test-token',
      appRootFolderName: 'TimeMachine',
    );
  });

  group('initialize', () {
    test('returns gdrive id and creates the app root folder', () async {
      final cloudId = await cloud.initialize();

      expect(cloudId, 'gdrive/user@example.com');
      final root = adapter.children(appDataFolder).single;
      expect(root.name, 'TimeMachine');
      expect(root.mimeType, folderMimeType);
    });

    test('reuses an existing app root folder', () async {
      adapter.files['existing'] = DriveFile(
        id: 'existing',
        name: 'TimeMachine',
        parentId: appDataFolder,
        mimeType: folderMimeType,
        createdTime: DateTime.utc(2023),
      );

      await cloud.initialize();

      expect(adapter.children(appDataFolder).single.id, 'existing');
    });

    test('throws when no token can be provided', () async {
      final anon = GoogleDriveCloud(
        client: adapter.client(),
        tokenProvider: () async => 'provider-token',
      );

      final failing = GoogleDriveCloud(
        client: adapter.client(),
        tokenProvider: () async => throw Exception('Not signed in'),
      );

      expect(failing.initialize(), throwsException);
      expect(failing.onPush(
        path: 'files/a.jpg',
        fileData: Uint8List.fromList([1]),
      ), throwsException);
      expect(anon.initialize(), completes);
    });

    test('uses the tokenProvider result for authorization', () async {
      final provided = GoogleDriveCloud(
        client: adapter.client(),
        tokenProvider: () async => 'provider-token',
      );

      await provided.initialize();
      await provided.onPush(
        path: 'files/a.jpg',
        fileData: Uint8List.fromList([1]),
        mimeType: 'image/jpeg',
      );

      expect(
        adapter.authorizationHeaders,
        everyElement('Bearer provider-token'),
      );
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
      final encoded = encodeName(metadata.id);

      final appRoot = childId(adapter, appDataFolder, 'TimeMachine');
      final models = adapter.children(childId(adapter, appRoot, 'models'));
      final records = models.firstWhere((f) => f.name == 'records');
      final modelFile = adapter.children(records.id).single;
      expect(modelFile.name, encoded);

      final listed = await cloud.listRecords('records');
      expect(listed.single.id, metadata.id);
    });

    test('re-saving an id updates the existing drive file', () async {
      final existing = await cloud.saveRecord('records', null, {'v': 1});
      final appRoot = childId(adapter, appDataFolder, 'TimeMachine');
      final recordFolder = adapter.children(
        childId(adapter, childId(adapter, appRoot, 'models'), 'records'),
      );

      await cloud.saveRecord(
        'records',
        existing,
        {'v': 2},
      );

      expect(recordFolder.length, 1);
      final data = await cloud.getRecord('records', existing.id);
      expect(data, {'v': 2});
    });

    test('deleteRecord removes the drive file', () async {
      final metadata = await cloud.saveRecord('pictures', null, {'id': 'd'});

      await cloud.deleteRecord('pictures', metadata.id);

      expect(
        cloud.getRecord('pictures', metadata.id),
        throwsException,
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

      final filesFolder = childId(
        adapter,
        childId(adapter, appDataFolder, 'TimeMachine'),
        'files',
      );
      final photos = adapter.children(filesFolder)
          .firstWhere((f) => f.name == 'photos');
      final year = adapter.children(photos.id)
          .firstWhere((f) => f.name == '2024');
      final file = adapter.children(year.id).single;
      expect(file.name, 'img.jpg');
      expect(file.mimeType, 'image/jpeg');
      expect(await cloud.downloadFile('files/photos/2024/img.jpg'), bytes);
    });

    test('re-upload updates the existing drive file', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);
      await cloud.uploadFile(
        name: 'img.jpg',
        fileData: Uint8List.fromList([9]),
      );
      final filesFolder = childId(
        adapter,
        childId(adapter, appDataFolder, 'TimeMachine'),
        'files',
      );

      expect(adapter.children(filesFolder).length, 1);
      expect(await cloud.downloadFile('files/img.jpg'),
          Uint8List.fromList([9]));
    });

    test('deleteFile removes the drive file', () async {
      await cloud.uploadFile(name: 'img.jpg', fileData: bytes);

      await cloud.deleteFile('files/img.jpg');

      expect(cloud.downloadFile('files/img.jpg'), throwsException);
      final filesFolder = childId(
        adapter,
        childId(adapter, appDataFolder, 'TimeMachine'),
        'files',
      );
      expect(adapter.children(filesFolder), isEmpty);
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
      final recordFile = adapter.files.values
          .firstWhere((f) => f.name == encodeName(metadata.id));
      adapter.addChange(fileId: recordFile.id);

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events, hasLength(1));
      expect(events.first.runtimeType.toString(), 'CloudInsertedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, metadata.id);
    });

    test('publishes a delete event when a file is removed', () async {
      final metadata = await cloud.saveRecord('records', null, {'v': 1});
      final recordFile = adapter.files.values
          .firstWhere((f) => f.name == encodeName(metadata.id));
      adapter.addChange(fileId: recordFile.id, removed: true);

      final events = await _collectEvents(cloud, () => cloud.pollChanges());

      expect(events.first.runtimeType.toString(), 'CloudDeletedEvent');
      expect(events.first.collection, 'records');
      expect(events.first.metadata.id, metadata.id);
    });
  });
}

/// Subscribes to [cloud]'s change stream, runs [trigger], then collects every
/// event that was delivered while the subscription was active.
Future<List<dynamic>> _collectEvents(
  GoogleDriveCloud cloud,
  Future<void> Function() trigger,
) async {
  final events = <dynamic>[];
  final sub = cloud.changes.listen(events.add);
  await trigger();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return events;
}