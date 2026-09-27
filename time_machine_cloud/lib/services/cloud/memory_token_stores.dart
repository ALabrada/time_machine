import 'dropbox_token_store.dart';
import 'google_drive_token_store.dart';
import 'nextcloud_token_store.dart';
import 'yandex_disk_token_store.dart';

/// Volatile token stores used as the default by the pure-Dart cloud providers.
/// They keep credentials only for the process lifetime, which is enough for a
/// stateless server hosting clouds; the Flutter app always injects the
/// matching `Secure*` store from `time_machine_net` to persist sessions.

class MemoryDropboxTokenStore implements DropboxTokenStore {
  MemoryDropboxTokenStore({this.session});

  DropboxSession? session;

  @override
  Future<DropboxSession?> read() async => session;

  @override
  Future<void> write(DropboxSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

class MemoryGoogleDriveTokenStore implements GoogleDriveTokenStore {
  MemoryGoogleDriveTokenStore({this.session});

  GoogleDriveSession? session;

  @override
  Future<GoogleDriveSession?> read() async => session;

  @override
  Future<void> write(GoogleDriveSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

class MemoryNextcloudTokenStore implements NextcloudTokenStore {
  MemoryNextcloudTokenStore({this.session});

  NextcloudSession? session;

  @override
  Future<NextcloudSession?> read() async => session;

  @override
  Future<void> write(NextcloudSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

class MemoryYandexDiskTokenStore implements YandexDiskTokenStore {
  MemoryYandexDiskTokenStore({this.session});

  YandexDiskSession? session;

  @override
  Future<YandexDiskSession?> read() async => session;

  @override
  Future<void> write(YandexDiskSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}