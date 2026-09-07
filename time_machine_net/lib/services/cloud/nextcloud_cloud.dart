import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/webdav.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/file_cloud_base.dart';
import 'package:time_machine_net/services/cloud/nextcloud_token_store.dart';

/// [FileCloudBase] implementation backed by a Nextcloud account, built on the
/// third-party `nextcloud` package (OpenAPI + WebDAV clients) instead of
/// hand-written HTTP requests.
///
/// All content lives under a dedicated root folder (`TimeMachine` by default)
/// inside the signed-in user's home, mirroring the layout used by
/// [GoogleDriveCloud] and [DropBoxCloud]:
/// `TimeMachine/models/<collection>/<id>` and `TimeMachine/files/<name>`.
/// Nextcloud's WebDAV has no convenient per-file custom metadata API here, so
/// record metadata is stored inside the encrypted record body and decoded
/// lazily by [FileCloudBase.listRecords].
///
/// Authentication uses an app password (HTTP Bearer app-password auth), which
/// the `nextcloud` package recommends over plain user credentials. Change
/// notifications are provided through the [EventfulFileCloud] mixin: after
/// [initialize] the cloud snapshots every collection folder and polls them on
/// a timer, publishing inserted/updated/deleted events whenever the
/// server-side ETag of an entry changed or an entry disappeared.
class NextCloudCloud extends FileCloudBase with EventfulFileCloud {
  NextCloudCloud({
    this.tokenStore = const SecureNextcloudTokenStore(),
    this.appRootFolderName = 'TimeMachine',
    this.pollInterval = const Duration(minutes: 1),
    super.encryptionKey,
    NextcloudClient? client,
  }) : _injectedClient = client {
    if (client != null) {
      _connectClient();
    }
  }

  /// Persists the session across launches so it can be restored without
  /// re-entering credentials.
  final NextcloudTokenStore tokenStore;

  final String appRootFolderName;

  /// How often the collection folders are polled for remote changes.
  final Duration pollInterval;

  NextcloudClient? _client;
  WebDavClient? _webDav;

  /// A client supplied at construction (e.g. in tests) and restored by
  /// [_connectClient] after [logout] released the previous connection.
  final NextcloudClient? _injectedClient;

  NextcloudSession? _session;
  bool _signedOut = false;

  Timer? _pollTimer;
  bool _polling = false;
  bool _pollingStarted = false;

  /// Last known ETag per entry name for every collection folder, used to
  /// detect inserts, updates and deletions between two polls.
  final Map<String, Map<String, String>> _snapshots = {};

  final Set<String> _ensuredFolders = {};

  /// Builds the WebDAV client. Called by the constructor and again by
  /// [initialize] when [logout] had released it.
  void _connectClient() {
    if (_webDav != null) return;
    final injected = _injectedClient;
    if (injected != null) {
      _client = injected;
      _webDav = injected.webdav;
      return;
    }
    final session = _session;
    final client = NextcloudClient(
      Uri.parse(session!.serverUrl),
      loginName: session.loginName,
      appPassword: session.appPassword,
    );
    _client = client;
    _webDav = client.webdav;
  }

  /// Drops the session client so its socket pool can be reclaimed.
  void _releaseClient() {
    _client?.close();
    _client = null;
    _webDav = null;
  }

  /// Runs no OAuth consent flow: Nextcloud is authenticated with an app
  /// password that the user generates in their Nextcloud web UI
  /// (Personal settings → Security → App passwords). The resulting
  /// [NextcloudSession] is handed to [NextcloudTokenStore.write].
  static Future<NextcloudSession> authorize({
    required String serverUrl,
    required String loginName,
    required String appPassword,
  }) async {
    if (Uri.tryParse(serverUrl) == null || serverUrl.isEmpty) {
      throw ArgumentError('serverUrl must be a valid URL');
    }
    return NextcloudSession(
      serverUrl: serverUrl,
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  @override
  Future<String> initialize() async {
    final session = await tokenStore.read();
    if (session == null ||
        session.appPassword.isEmpty ||
        session.loginName.isEmpty) {
      throw Exception('No Nextcloud session available');
    }
    _signedOut = false;
    _session = session;
    _connectClient();

    await _ensureRootFolder();
    for (final collection in collectionNames.values) {
      await _ensureFolderPath(p.join(FileCloudBase.modelsDir, collection));
    }
    await _ensureFolderPath(FileCloudBase.filesDir);
    await _resetSnapshots();
    _startPolling();
    publishEvent(const CloudReconnectedEvent());
    return 'nextcloud/${session.loginName}';
  }

  void _startPolling() {
    if (_pollingStarted) return;
    _pollingStarted = true;
    _pollTimer = Timer.periodic(pollInterval, (_) => pollChanges());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollingStarted = false;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  /// Clears the persisted session, releases the client connection and stops
  /// polling. Every subsequent API call fails until the cloud is
  /// re-authenticated; the same instance can be reused after a new session
  /// was stored and [initialize] ran again.
  Future<void> logout() async {
    _signedOut = true;
    _session = null;
    _releaseClient();
    _snapshots.clear();
    _stopPolling();
    await tokenStore.clear();
  }

  WebDavClient _requireWebDav() {
    final webDav = _webDav;
    if (_signedOut || webDav == null) {
      throw Exception('Not signed in');
    }
    return webDav;
  }

  /// The signed-in account, once [initialize] has persisted it. Mirrors
  /// `DropBoxCloud.userEmail`.
  String? get userEmail => _session?.loginName;

  @override
  Stream<CloudFileEntry> onList(String path) async* {
    for (final entry in await _listAll(path)) {
      if (entry.isDirectory) continue;
      yield CloudFileEntry(name: entry.name);
    }
  }

  @override
  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
    String? metadata,
  }) async {
    await _ensureFolderPath(p.dirname(path));
    await _requireWebDav().put(fileData, _path(path));
  }

  @override
  Future<String> onDelete(String path) async {
    try {
      await _requireWebDav().delete(_path(path));
    } on DynamiteStatusCodeException catch (error) {
      // Deleting a missing file yields a 404; treat it as success.
      if (error.statusCode != 404) {
        rethrow;
      }
    }
    return path;
  }

  @override
  Future<Uint8List> onPull(String path) async {
    try {
      return await _requireWebDav().get(_path(path));
    } on DynamiteStatusCodeException catch (error) {
      if (error.statusCode == 404) {
        throw Exception('Not found: $path');
      }
      rethrow;
    }
  }

  /// Polls every collection folder and publishes change events for entries
  /// whose ETag changed since the previous poll. Exposed for testing.
  @visibleForTesting
  Future<void> pollChanges() async {
    if (_signedOut || _polling) return;
    _polling = true;
    try {
      for (final collection in collectionNames.values) {
        Map<String, String> current;
        try {
          current = await _snapshotFor(collection);
        } catch (_) {
          // Transient network/API error: retry on the next poll.
          continue;
        }
        final previous = _snapshots[collection] ?? const {};
        for (final name in current.keys) {
          final oldEtag = previous[name];
          final recordPath = _recordPath(collection, name);
          if (oldEtag == null) {
            await publishFileInserted(path: recordPath);
          } else if (oldEtag != current[name]) {
            await publishFileUpdated(path: recordPath);
          }
        }
        for (final name in previous.keys.where((n) => !current.containsKey(n))) {
          await publishFileDeleted(path: _recordPath(collection, name));
        }
        _snapshots[collection] = current;
      }
    } finally {
      _polling = false;
    }
  }

  Future<Map<String, String>> _snapshotFor(String collection) async {
    final entries = await _listAll(p.join(FileCloudBase.modelsDir, collection));
    return {
      for (final entry in entries.where((entry) => !entry.isDirectory))
        entry.name: entry.etag ?? '',
    };
  }

  Future<void> _resetSnapshots() async {
    for (final collection in collectionNames.values) {
      _snapshots[collection] = await _snapshotFor(collection);
    }
  }

  Future<List<WebDavFile>> _listAll(String relativePath) async {
    final result = await _requireWebDav().propfind(
      _path(relativePath),
      depth: WebDavDepth.one,
    );
    return result.toWebDavFiles();
  }

  Future<void> _ensureFolderPath(String folderPath) async {
    if (folderPath == '' || folderPath == '.') {
      await _ensureRootFolder();
      return;
    }
    if (_ensuredFolders.contains(folderPath)) return;
    final parent = p.dirname(folderPath);
    await _ensureFolderPath(parent);
    try {
      await _requireWebDav().mkcol(_path(folderPath));
    } on DynamiteStatusCodeException catch (error) {
      // Creating an existing collection yields a 405; treat it as already
      // there from a previous session.
      if (error.statusCode != 405) {
        rethrow;
      }
    }
    _ensuredFolders.add(folderPath);
  }

  Future<void> _ensureRootFolder() async {
    if (_ensuredFolders.contains('')) return;
    try {
      await _requireWebDav().mkcol(_path(appRootFolderName));
    } on DynamiteStatusCodeException catch (error) {
      // The root folder already exists from a previous session.
      if (error.statusCode != 405) {
        rethrow;
      }
    }
    _ensuredFolders.add('');
  }

  /// Turns a package-relative [FileCloudBase] path into a WebDAV [PathUri]
  /// below the app root folder (relative to the user's home, which is where
  /// `/remote.php/webdav` is rooted).
  PathUri _path(String relativePath) =>
      PathUri.parse('$appRootFolderName/$relativePath');

  String _recordPath(String collection, String encodedId) =>
      p.join(FileCloudBase.modelsDir, collection, encodedId);
}
