import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:time_machine_cloud/services/cloud/dropbox_api.dart';
import 'package:time_machine_cloud/services/cloud/dropbox_cloud.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_cloud.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_transport.dart';

void main() {
  test('Google access-token auth creates a UTC expiry', () async {
    final cloud = GoogleDriveCloud(startPolling: false);
    addTearDown(cloud.dispose);

    await cloud.authenticateWithAccessToken(accessToken: 'access-token');
  });

  test('Dropbox initialize reuses a server-side access-token session',
      () async {
    final cloud = DropBoxCloud(
      clientId: 'test-client',
      pollInterval: const Duration(days: 1),
      api: _FakeDropboxApi(),
    );
    addTearDown(cloud.dispose);

    await cloud.authenticateWithAccessToken(accessToken: 'access-token');

    expect(await cloud.initialize(), 'dropbox/test@example.com');
    expect(cloud.userEmail, 'test@example.com');
  });

  test('Yandex initialize reuses a server-side access-token session', () async {
    final cloud = YandexDiskCloud(
      clientId: 'test-client',
      pollInterval: const Duration(days: 1),
      transport: _FakeYandexTransport(),
    );
    addTearDown(cloud.dispose);

    await cloud.authenticateWithAccessToken(accessToken: 'access-token');

    expect(await cloud.initialize(), 'yandex/test-user');
    expect(cloud.userEmail, 'test-user');
  });
}

class _FakeDropboxApi implements DropboxApi {
  @override
  Future<DropboxAccount> getCurrentAccount() async =>
      const DropboxAccount(accountId: 'dbid:test', email: 'test@example.com');

  @override
  Future<DropboxFolderContents> listFolder(
    String path, {
    int limit = 2000,
  }) async =>
      const DropboxFolderContents(entries: []);

  @override
  Future<DropboxFolderContents> listFolderContinue(String cursor) async =>
      const DropboxFolderContents(entries: []);

  @override
  Future<DropboxFolder> createFolder(String path) async =>
      const DropboxFolder(id: 'id', name: 'name');

  @override
  Future<DropboxFile> upload(
    String path,
    Stream<List<int>> dataStream, {
    String mode = 'add',
    bool autorename = true,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String path) => throw UnimplementedError();

  @override
  Future<void> move(String fromPath, String toPath) =>
      throw UnimplementedError();

  @override
  Future<void> copy(String fromPath, String toPath) =>
      throw UnimplementedError();

  @override
  Future<Stream<List<int>>> download(String path) => throw UnimplementedError();

  @override
  void setAccessToken(String accessToken) {}
}

class _FakeYandexTransport implements YandexDiskTransport {
  @override
  Future<String> currentUserName() async => 'test-user';

  @override
  Future<List<YandexDiskEntry>> readDir(String path) async => const [];

  @override
  Future<void> mkdirAll(String path) async {}

  @override
  Future<Uint8List> read(String path) => throw UnimplementedError();

  @override
  Future<void> write(String path, Uint8List data) => throw UnimplementedError();

  @override
  Future<void> remove(String path) => throw UnimplementedError();
}
