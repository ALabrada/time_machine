import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropbox_api/dropbox_api.dart' as dropbox;
import 'package:flutter/foundation.dart';
// The concrete REST transport is not exported by `dropbox_api`; this is the
// package's own HTTP implementation of its `OAuth2RestClient` interface.
// ignore: implementation_imports
import 'package:oauth2restclient/src/rest_client/http_oauth2_rest_client.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/dropbox_token_store.dart';
import 'package:time_machine_net/services/cloud/file_cloud_base.dart';

/// [FileCloudBase] implementation backed by a Dropbox account, built on the
/// third-party `dropbox_api` package instead of hand-written HTTP requests.
///
/// All content lives under a dedicated root folder (`/TimeMachine` by
/// default), mirroring the layout used by [GoogleDriveCloud]:
/// `/TimeMachine/models/<collection>/<id>` and `/TimeMachine/files/<name>`.
/// Dropbox has no custom file properties, so record metadata is stored inside
/// the encrypted record body and decoded lazily by [FileCloudBase.listRecords].
///
/// Change notifications are provided through the [EventfulFileCloud] mixin:
/// after [initialize] the cloud snapshots every collection folder and polls
/// them on a timer, publishing inserted/updated/deleted events whenever the
/// server-side revision (`rev`) of an entry changed or an entry disappeared.
class DropBoxCloud extends FileCloudBase with EventfulFileCloud {
  DropBoxCloud({
    required this.clientId,
    this.tokenStore = const SecureDropboxTokenStore(),
    this.appRootFolderName = 'TimeMachine',
    this.pollInterval = const Duration(minutes: 1),
    String? redirectUri,
    super.encryptionKey,
    HttpOAuth2RestClient? client,
    dropbox.DropboxApi? api,
  })  : redirectUri = redirectUri ?? defaultRedirectUri,
        _injectedApi = api,
        _externalClient = client {
    _connectApi();
  }

  /// OAuth 2 client identifier registered for this app at
  /// <https://www.dropbox.com/developers/apps>.
  final String clientId;

  /// Persists the session across launches so it can be restored without
  /// re-running the OAuth consent flow.
  final DropboxTokenStore tokenStore;

  final String appRootFolderName;

  /// How often the collection folders are polled for remote changes.
  final Duration pollInterval;

  /// Redirect URI of the registered Dropbox app. Only used to run (or refresh)
  /// the OAuth flow; defaults to a local loopback address.
  final String redirectUri;

  static const defaultRedirectUri = 'https://localhost:4690/';

  dropbox.DropboxApi? _api;
  HttpOAuth2RestClient? _restClient;

  /// Dependencies supplied at construction; restored by [_connectApi] after
  /// [logout] released the previous connection.
  final dropbox.DropboxApi? _injectedApi;
  final HttpOAuth2RestClient? _externalClient;

  DropboxSession? _session;
  bool _signedOut = false;

  Timer? _pollTimer;
  bool _polling = false;
  bool _pollingStarted = false;

  /// Last known revision per entry name for every collection folder, used to
  /// detect inserts, updates and deletions between two polls.
  final Map<String, Map<String, String>> _snapshots = {};

  final Set<String> _ensuredFolders = {};

  /// Builds the API connection. Called by the constructor and again by
  /// [initialize] when [logout] had released it.
  void _connectApi() {
    if (_api != null) return;
    final injected = _injectedApi;
    if (injected != null) {
      _api = injected;
      return;
    }
    _restClient = _externalClient ??
        HttpOAuth2RestClient(refreshToken: _refreshAccessToken);
    _api = dropbox.DropboxRestApi(_restClient!);
  }

  /// Drops the REST transport so its socket pool can be reclaimed. The
  /// package's client exposes no close method, so releasing is by reference.
  void _releaseApi() {
    _api = null;
    _restClient = null;
  }

  /// Runs the Dropbox OAuth consent flow through the `dropbox_api` package
  /// (Dropbox app or browser on mobile, loopback HTTP server on desktop) and
  /// returns the resulting session, ready to be persisted with
  /// [DropboxTokenStore.write].
  static Future<DropboxSession> authorize({
    required String clientId,
    String? redirectUri,
  }) async {
    final provider = dropbox.Dropbox(
      clientId: clientId,
      redirectUri: redirectUri ?? defaultRedirectUri,
    );
    final token = await provider.login();
    if (token == null || token.accessToken.isEmpty) {
      throw Exception('Dropbox authorization failed');
    }
    return DropboxSession(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken,
    );
  }

  Future<void> authenticate() async {
    final session = await authorize(
      clientId: clientId,
      redirectUri: redirectUri,
    );
    await tokenStore.write(session);
  }

  @override
  Future<String> initialize() async {
    final session = await tokenStore.read();
    if (session == null || session.accessToken.isEmpty) {
      throw Exception('No Dropbox session available');
    }
    _signedOut = false;
    _session = session;
    _connectApi();
    final restClient = _restClient;
    if (restClient != null) {
      restClient.accessToken = session.accessToken;
    }

    final account = await _requireApi().getCurrentAccount();
    await _persistAccount(account.email);
    await _ensureFolderPath(FileCloudBase.modelsDir);
    for (final collection in collectionNames.values) {
      await _ensureFolderPath(p.join(FileCloudBase.modelsDir, collection));
    }
    await _ensureFolderPath(FileCloudBase.filesDir);
    await _resetSnapshots();
    _startPolling();
    publishEvent(const CloudReconnectedEvent());
    return 'dropbox/${account.email}';
  }

  /// Records the signed-in account in the persisted session, so it is
  /// available without contacting the API later.
  Future<void> _persistAccount(String email) async {
    if (_session?.accountEmail == email) {
      return;
    }
    _session = _session!.copy(accountEmail: email);
    await tokenStore.write(_session!);
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

  /// Clears the persisted session, releases the API connection and stops
  /// polling. Every subsequent API call fails until the cloud is
  /// re-authenticated; the same instance can be reused after a new session
  /// was stored and [initialize] ran again.
  @override
  Future<void> logout() async {
    _signedOut = true;
    _session = null;
    _releaseApi();
    _snapshots.clear();
    _stopPolling();
    await tokenStore.clear();
  }

  /// Refreshes the access token using the stored refresh token. Wired into
  /// the REST client so expired short-lived tokens are renewed transparently.
  Future<String?> _refreshAccessToken() async {
    final refreshToken = _session?.refreshToken;
    if (_signedOut || refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    final provider = dropbox.Dropbox(
      clientId: clientId,
      redirectUri: redirectUri,
    );
    final token = await provider.refreshToken(refreshToken);
    if (token == null || token.accessToken.isEmpty) {
      return null;
    }
    _session = _session!.copy(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken.isEmpty ? null : token.refreshToken,
    );
    await tokenStore.write(_session!);
    return token.accessToken;
  }

  dropbox.DropboxApi _requireApi() {
    final api = _api;
    if (_signedOut || api == null) {
      throw Exception('Not signed in');
    }
    return api;
  }

  /// The signed-in account, once [initialize] has persisted it. Mirrors
  /// `SupabaseCloud.userEmail`.
  String? get userEmail => _session?.accountEmail;

  @override
  Stream<CloudFileEntry> onList(String path, {DateTime? since}) async* {
    for (final entry in await _listAll(path)) {
      if (!entry.isFile) continue;
      yield CloudFileEntry(name: entry.name);
    }
  }

  @override
  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
    String? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    await _ensureFolderPath(p.dirname(path));
    await _requireApi().upload(
      _absolute(path),
      Stream<List<int>>.value(fileData),
      mode: 'overwrite',
      autorename: false,
    );
  }

  @override
  Future<String> onDelete(String path) async {
    try {
      await _requireApi().delete(_absolute(path));
    } on HttpException catch (error) {
      // Deleting a missing file yields a conflict; treat it as success.
      if (!_isConflict(error)) {
        rethrow;
      }
    }
    return path;
  }

  @override
  Future<Uint8List> onPull(String path) async {
    final stream = await _requireApi().download(_absolute(path));
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Polls every collection folder and publishes change events for entries
  /// whose revision changed since the previous poll. Exposed for testing.
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
          final oldRev = previous[name];
          final recordPath = _recordPath(collection, name);
          if (oldRev == null) {
            await publishFileInserted(path: recordPath);
          } else if (oldRev != current[name]) {
            await publishFileUpdated(path: recordPath);
          }
        }
        for (final name
            in previous.keys.where((n) => !current.containsKey(n))) {
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
      for (final entry in entries.where((entry) => entry.isFile))
        entry.name: entry.rev ?? '',
    };
  }

  Future<void> _resetSnapshots() async {
    for (final collection in collectionNames.values) {
      _snapshots[collection] = await _snapshotFor(collection);
    }
  }

  Future<List<dropbox.DropboxFile>> _listAll(String relativePath) async {
    var response = await _requireApi().listFolder(_absolute(relativePath));
    final entries = [...response.entries];
    while (response.hasMore && response.cursor != null) {
      response = await _requireApi().listFolderContinue(response.cursor!);
      entries.addAll(response.entries);
    }
    return entries;
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
      await _requireApi().createFolder(_absolute(folderPath));
    } on HttpException catch (error) {
      // The folder already exists from a previous session.
      if (!_isConflict(error)) {
        rethrow;
      }
    }
    _ensuredFolders.add(folderPath);
  }

  Future<void> _ensureRootFolder() async {
    if (_ensuredFolders.contains('')) return;
    try {
      await _requireApi().createFolder('/$appRootFolderName');
    } on HttpException catch (error) {
      // The root folder already exists from a previous session.
      if (!_isConflict(error)) {
        rethrow;
      }
    }
    _ensuredFolders.add('');
  }

  /// Turns a package-relative [FileCloudBase] path into an absolute Dropbox
  /// path below the app root folder.
  String _absolute(String path) => '/${p.join(appRootFolderName, path)}';

  String _recordPath(String collection, String encodedId) =>
      p.join(FileCloudBase.modelsDir, collection, encodedId);

  /// The REST layer surfaces HTTP failures as [HttpException] messages like
  /// `HTTP request failed, statusCode=409`; conflicts mean "already exists".
  static bool _isConflict(HttpException error) =>
      error.message.contains('statusCode=409');
}
