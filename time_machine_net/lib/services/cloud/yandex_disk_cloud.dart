import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/file_cloud_base.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_auth.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_token_store.dart';
import 'package:time_machine_net/services/cloud/yandex_disk_transport.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// [FileCloudBase] implementation backed by a Yandex Disk account, talking to
/// the REST API (`https://cloud-api.yandex.net`, see
/// [RestYandexDiskTransport]).
///
/// All content lives inside the application's dedicated Yandex Disk app
/// folder, addressed through the locale-independent `app:/` shortcut that
/// Yandex resolves to the connected app's folder automatically. The layout
/// mirrors the one used by [GoogleDriveCloud]:
/// `app:/models/<collection>/<id>` and `app:/files/<name>`.
/// Yandex Disk has no server-side custom properties, so record metadata is
/// stored inside the encrypted record body and decoded lazily by
/// [FileCloudBase.listRecords].
///
/// Change notifications are provided through the [EventfulFileCloud] mixin:
/// after [initialize] the cloud snapshots every collection folder and polls
/// them on a timer, publishing inserted/updated/deleted events whenever the
/// server-side revision (a Yandex content hash, falling back to size + mtime)
/// of an entry changed or an entry disappeared.
///
/// Authorization to the web/app shell is the [YandexDiskAuth] OAuth flow
/// (authorization code + PKCE, no client secret). Access tokens live ~1 year,
/// so [initialize] transparently refreshes an expired stored token before
/// connecting.
class YandexDiskCloud extends FileCloudBase with EventfulFileCloud {
  YandexDiskCloud({
    required this.clientId,
    this.tokenStore = const SecureYandexDiskTokenStore(),
    this.pollInterval = const Duration(minutes: 1),
    String? redirectUri,
    String? customUriScheme,
    this.redirectStream,
    this.openBrowser,
    super.encryptionKey,
    YandexDiskTransport? transport,
    YandexDiskAuth? auth,
  })  : redirectUri = redirectUri ?? defaultRedirectUri,
        customUriScheme = customUriScheme ?? defaultCustomUriScheme,
        _injectedTransport = transport,
        _injectedAuth = auth;

  /// OAuth 2 client identifier registered for this app at
  /// <https://oauth.yandex.ru>.
  final String clientId;

  /// Persists the session across launches so it can be restored without
  /// re-running the OAuth consent flow.
  final YandexDiskTokenStore tokenStore;

  /// How often the collection folders are polled for remote changes.
  final Duration pollInterval;

  /// Redirect URI of the registered Yandex OAuth app. Only used to run (or
  /// refresh) the OAuth flow.
  final String redirectUri;

  /// Uri scheme that the OAuth callback is delivered on; must match the
  /// redirect URI scheme registered for the OAuth app.
  final String customUriScheme;

  /// Stream of custom-scheme URLs delivered to the app (deep links). The
  /// stream must be broadcast-friendly: it is subscribed before the browser is
  /// opened, and must surface the Yandex redirect once the user consents.
  final Stream<Uri>? redirectStream;

  /// Opens [Uri]s in the system browser for the OAuth consent flow. When
  /// null, the platform default browser is used.
  final void Function(Uri uri)? openBrowser;

  static const defaultRedirectUri = YandexDiskAuth.defaultRedirectUri;
  static const defaultCustomUriScheme = YandexDiskAuth.defaultCustomUriScheme;

  YandexDiskTransport? _transport;

  /// Dependencies supplied at construction; restored by [_connect] after
  /// [logout] released the previous connection.
  final YandexDiskTransport? _injectedTransport;
  final YandexDiskAuth? _injectedAuth;

  YandexDiskSession? _session;
  bool _signedOut = false;

  Timer? _pollTimer;
  bool _polling = false;
  bool _pollingStarted = false;

  /// Last known revision per entry name for every collection folder, used to
  /// detect inserts, updates and deletions between two polls.
  final Map<String, Map<String, String>> _snapshots = {};

  final Set<String> _ensuredFolders = {};

  /// Builds the REST transport for the current access token. Called by
  /// [initialize] and again when [logout] had released it.
  void _connect(String accessToken) {
    final injected = _injectedTransport;
    _transport = injected ?? RestYandexDiskTransport(accessToken);
  }

  /// Drops the transport so its socket pool can be reclaimed.
  void _release() {
    _transport = null;
  }

  /// Runs the Yandex OAuth consent flow through the system browser, using the
  /// [app_links] redirect stream wired in the shell, and persists the
  /// resulting session in [YandexDiskTokenStore].
  static Future<YandexDiskSession> authorize({
    required String clientId,
    String? redirectUri,
    String? customUriScheme,
    required Stream<Uri> redirectStream,
    void Function(Uri uri)? openBrowser,
    YandexDiskAuth? auth,
  }) async {
    final oauth =
        auth ?? YandexDiskAuth(redirectUri: redirectUri, customUriScheme: customUriScheme);
    final launch = openBrowser ?? _launchBrowser;
    return oauth.obtainSession(
      clientId: clientId,
      openBrowser: launch,
      redirectStream: redirectStream,
    );
  }

  Future<void> authenticate() async {
    final stream = redirectStream;
    if (stream == null) {
      throw StateError('Yandex OAuth requires a redirect stream');
    }
    final session = await authorize(
      clientId: clientId,
      redirectUri: redirectUri,
      customUriScheme: customUriScheme,
      redirectStream: stream,
      openBrowser: openBrowser ?? _launchBrowser,
      auth: _injectedAuth,
    );
    await tokenStore.write(session);
  }

  static Future<void> _launchBrowser(Uri uri) async {
    final opened = await launchUrlString(uri.toString());
    if (!opened) {
      throw Exception('Could not open the browser');
    }
  }

  @override
  Future<String> initialize() async {
    final session = await tokenStore.read();
    if (session == null || session.accessToken.isEmpty) {
      throw Exception('No Yandex Disk session available');
    }
    _signedOut = false;
    _session = session;
    if (_isExpired(session)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed != null) {
        _session = refreshed;
        await tokenStore.write(refreshed);
      }
    }

    _connect(_session!.accessToken);
    final login = await _requireTransport().currentUserName();
    await _persistAccount(login);
    await _ensureFolderPath(FileCloudBase.modelsDir);
    for (final collection in collectionNames.values) {
      await _ensureFolderPath(p.join(FileCloudBase.modelsDir, collection));
    }
    await _ensureFolderPath(FileCloudBase.filesDir);
    await _resetSnapshots();
    _startPolling();
    publishEvent(const CloudReconnectedEvent());
    return 'yandex/$login';
  }

  /// Records the signed-in account in the persisted session, so it is
  /// available without contacting the API later.
  Future<void> _persistAccount(String login) async {
    if (_session?.userEmail == login) {
      return;
    }
    _session = _session!.copy(userEmail: login);
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

  /// Clears the persisted session, releases the transport and stops polling.
  /// Every subsequent API call fails until the cloud is re-authenticated; the
  /// same instance can be reused after a new session was stored and
  /// [initialize] ran again.
  @override
  Future<void> logout() async {
    _signedOut = true;
    _session = null;
    _release();
    _snapshots.clear();
    _stopPolling();
    await tokenStore.clear();
  }

  /// Refreshes the access token using the stored refresh token. Returns
  /// `null` when there is nothing to refresh with, the refresh was rejected
  /// or a transient network error occurred (the current token may still be
  /// valid, so callers fall back to it).
  Future<YandexDiskSession?> _refreshAccessToken() async {
    final refreshToken = _session?.refreshToken;
    final oauth = _injectedAuth;
    if (_signedOut || refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    try {
      final auth = oauth ??
          YandexDiskAuth(
            redirectUri: redirectUri,
            customUriScheme: customUriScheme,
          );
      final result = await auth.refresh(refreshToken, clientId: clientId);
      if (result == null) {
        return null;
      }
      return _session!.copy(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken.isEmpty
            ? refreshToken
            : result.refreshToken,
        expiresAt: result.expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isExpired(YandexDiskSession session) {
    final expiresAt = session.expiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now());
  }

  YandexDiskTransport _requireTransport() {
    final transport = _transport;
    if (_signedOut || transport == null) {
      throw Exception('Not signed in');
    }
    return transport;
  }

  /// The signed-in account, once [initialize] has persisted it.
  String? get userEmail => _session?.userEmail;

  @override
  Stream<CloudFileEntry> onList(String path, {DateTime? since}) async* {
    for (final entry in await _requireTransport().readDir(_absolute(path))) {
      if (entry.isDir) continue;
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
    await _requireTransport().write(_absolute(path), fileData);
  }

  @override
  Future<String> onDelete(String path) async {
    // The REST DELETE is idempotent: the transport treats a missing resource
    // as a successful delete.
    await _requireTransport().remove(_absolute(path));
    return path;
  }

  @override
  Future<Uint8List> onPull(String path) async =>
      _requireTransport().read(_absolute(path));

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
    final entries = await _requireTransport()
        .readDir(_absolute(p.join(FileCloudBase.modelsDir, collection)));
    return {
      for (final entry in entries.where((entry) => !entry.isDir))
        entry.name: _revisionKey(entry),
    };
  }

  Future<void> _resetSnapshots() async {
    for (final collection in collectionNames.values) {
      _snapshots[collection] = await _snapshotFor(collection);
    }
  }

  /// A Yandex content hash (`sha256`/`md5`) is the strongest change signal.
  /// When a listing omits one, fall back to a size + mtime fingerprint.
  String _revisionKey(YandexDiskEntry entry) => entry.eTag.isNotEmpty
      ? entry.eTag
      : '${entry.mTime?.millisecondsSinceEpoch ?? 0}:${entry.size}';

  Future<void> _ensureFolderPath(String folderPath) async {
    if (folderPath == '' || folderPath == '.') {
      await _ensureRootFolder();
      return;
    }
    if (_ensuredFolders.contains(folderPath)) return;
    final parent = p.dirname(folderPath);
    await _ensureFolderPath(parent);
    // The REST create-folder returns 409 for an existing folder; the
    // transport treats it as a success.
    await _requireTransport().mkdirAll(_absolute(folderPath));
    _ensuredFolders.add(folderPath);
  }

  Future<void> _ensureRootFolder() async {
    if (_ensuredFolders.contains('')) return;
    await _requireTransport().mkdirAll(_absolute(''));
    _ensuredFolders.add('');
  }

  /// Turns a package-relative [FileCloudBase] path into an absolute path below
  /// the application's dedicated app folder, using the `app:/` shortcut that
  /// Yandex resolves to the app folder regardless of its real name.
  String _absolute(String path) => path.isEmpty ? 'app:/' : 'app:/$path';

  String _recordPath(String collection, String encodedId) =>
      p.join(FileCloudBase.modelsDir, collection, encodedId);
}