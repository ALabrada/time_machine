import 'dart:async';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/file_cloud_base.dart';
import 'package:time_machine_net/services/cloud/google_drive_token_store.dart';

class GoogleDriveCloud extends FileCloudBase with EventfulFileCloud {
  GoogleDriveCloud({
    http.Client? client,
    bool closeClient = false,
    GoogleDriveTokenStore? tokenStore,
    this.appRootFolderName = 'TimeMachine',
    this.pollInterval = const Duration(minutes: 1),
    super.encryptionKey,
  }) : tokenStore = tokenStore ?? const SecureGoogleDriveTokenStore(),
       _ownsClient = client == null || closeClient {
    _baseClient = client ?? http.Client();
    _drive = drive.DriveApi(_baseClient);
  }

  /// Grants the `driver`. Given an authenticated [http.Client], only the
  /// Drive app data scope is requested.
  static const appDataScope = drive.DriveApi.driveAppdataScope;

  static const folderMimeType = 'application/vnd.google-apps.folder';
  static const appDataFolder = 'appDataFolder';

  late drive.DriveApi _drive;
  late final http.Client _baseClient;
  final bool _ownsClient;

  /// Stores the persisted credentials used to restore the session.
  final GoogleDriveTokenStore tokenStore;

  /// Set after [logout] so no further token is presented until re-auth.
  bool _signedOut = false;

  /// The session read from [tokenStore] during [initialize], kept so the
  /// account email can be persisted back once known.
  GoogleDriveSession? _restoredSession;

  http.Client? _sessionClient;
  final String appRootFolderName;
  final Duration pollInterval;

  Timer? _pollTimer;
  String? _nextChangeToken;
  bool _polling = false;
  bool _pollingStarted = false;

  final Map<String, String> _folderIds = {};
  final Map<String, String> _collectionByFolderId = {};
  String? _rootFolderId;

  /// Signs out, clearing the persisted credentials and the current session
  /// so every subsequent request fails until the cloud is re-authenticated.
  Future<void> logout() async {
    _signedOut = true;
    final sessionClient = _sessionClient;
    _sessionClient = null;
    if (sessionClient != null && sessionClient != _baseClient) {
      sessionClient.close();
    }
    _drive = drive.DriveApi(_RejectingClient());
    await tokenStore.clear();
  }

  /// Restores a previously signed-in session from the saved refresh token
  /// when no credentials were supplied at construction.
  Future<void> _restoreSession() async {
    if (_signedOut) {
      return;
    }
    final session = await tokenStore.read();
    if (session == null) {
      return;
    }
    final clientId = session.clientId;
    final refreshToken = session.refreshToken;
    if (clientId.isEmpty || refreshToken.isEmpty) {
      return;
    }
    _restoredSession = session;
    final client = await auth_io.clientViaRefreshToken(
      auth.ClientId(clientId, null),
      refreshToken,
      const [appDataScope],
      baseClient: _baseClient,
    );
    _signedOut = false;
    _sessionClient = client;
    _drive = drive.DriveApi(client);
  }

  @override
  Future<String> initialize() async {
    await _restoreSession();
    final about = await _drive.about.get($fields: 'user(emailAddress)');
    final email = about.user?.emailAddress ?? 'unknown';
    await _persistUserEmail(email);
    await _ensureRootFolder();
    await _initCollectionFolders();
    final tokenResult = await _drive.changes.getStartPageToken();
    _nextChangeToken = tokenResult.startPageToken;
    _startPolling();
    publishEvent(const CloudReconnectedEvent());
    return 'gdrive/$email';
  }

  /// Records the signed-in account in the persisted session, so it is
  /// available without contacting the API later.
  Future<void> _persistUserEmail(String email) {
    final session = _restoredSession;
    if (session == null || session.userEmail == email) {
      return Future.value();
    }
    _restoredSession = GoogleDriveSession(
      refreshToken: session.refreshToken,
      clientId: session.clientId,
      userEmail: email,
    );
    return tokenStore.write(_restoredSession!);
  }

  Future<void> _initCollectionFolders() async {
    for (final collection in collectionNames.values) {
      final folderId = await _ensureFolderPath(p.join(FileCloudBase.modelsDir, collection));
      _collectionByFolderId[folderId] = collection;
    }
  }

  void _startPolling() {
    if (_pollingStarted) return;
    _pollingStarted = true;
    _pollTimer = Timer.periodic(pollInterval, (_) => pollChanges());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final sessionClient = _sessionClient;
    if (sessionClient != null && sessionClient != _baseClient) {
      sessionClient.close();
    }
    if (_ownsClient && _baseClient != sessionClient) {
      _baseClient.close();
    }
    super.dispose();
  }

  /// Polls the Drive `changes` API for appDataFolder activity and publishes
  /// cloud events. Exposed for testing.
  @visibleForTesting
  Future<void> pollChanges() async {
    final token = _nextChangeToken;
    if (token == null || _polling) return;
    _polling = true;
    try {
      final result = await _drive.changes.list(
        token,
        spaces: appDataFolder,
        includeRemoved: true,
        pageSize: 100,
        $fields: 'nextPageToken,changes('
            'fileId,removed,'
            'file(id,name,parents,appProperties))',
      );
  
      for (final change in result.changes ?? const []) {

        _handleChange(change);
      }
      _nextChangeToken = result.nextPageToken ?? token;
    } catch (_) {
      // Transient network/API error: retry on the next poll.
    } finally {
      _polling = false;
    }
  }

  void _handleChange(drive.Change change) {
    final file = change.file;
    final collection = _collectionFromParents(file?.parents);
    if (collection == null) return;
    final name = file?.name;
    if (name == null) return;
    final recordId = Uri.decodeComponent(name);

    final path = p.join(
      FileCloudBase.modelsDir,
      collection,
      Uri.encodeComponent(recordId),
    );
    final metadataJson = file?.appProperties?[FileCloudBase.metadataKey];

    if (change.removed == true) {
      publishFileDeleted(path: path, metadata: metadataJson);
    } else {
      publishFileInserted(path: path, metadata: metadataJson);
    }
  }

  String? _collectionFromParents(List<String>? parents) {
    if (parents == null) return null;
    for (final parentId in parents) {
      final collection = _collectionByFolderId[parentId];
      if (collection != null) return collection;
    }
    return null;
  }

  @override
  Stream<CloudFileEntry> onList(String path) async* {
    final folderId = await _resolveFolder(path);
    if (folderId == null) return;
    await for (final file in _listFolder(folderId)) {
      final fileName = file.name;
      if (fileName != null) {
        yield CloudFileEntry(
          name: fileName,
          metadata: file.appProperties?[FileCloudBase.metadataKey],
        );
      }
    }
  }

  @override
  Future<void> onPush({
    required String path,
    required Uint8List fileData,
    String? mimeType,
    String? metadata,
  }) async {
    final parentDir = p.dirname(path);
    final name = p.basename(path);
    final parentId = await _ensureFolderPath(parentDir);
    final existing = await _findChild(parentId, name);
    final appProperties =
        metadata == null ? null : {FileCloudBase.metadataKey: metadata};
    if (existing != null) {
      final driveFileId = existing.id!;
      await _updateFile(driveFileId, fileData, mimeType, appProperties);
    } else {
      await _createFile(parentId, name, fileData, mimeType, appProperties);
    }
  }

  @override
  Future<String> onDelete(String path) async {
    final fileId = await _resolveFileId(path);
    if (fileId != null) {
      await _deleteFile(fileId);
    }
    return path;
  }

  @override
  Future<Uint8List> onPull(String path) async {
    final fileId = await _resolveFileId(path);
    if (fileId == null) {
      throw Exception('Not found: $path');
    }
    return _downloadFile(fileId);
  }

  Future<String?> _resolveFileId(String path) async {
    final parentDir = p.dirname(path);
    final name = p.basename(path);
    final parentId = await _resolveFolder(parentDir);
    if (parentId == null) return null;
    final child = await _findChild(parentId, name);
    return child?.id;
  }

  Future<String?> _resolveFolder(String folderPath) async {
    if (folderPath == '' || folderPath == '.') return _rootFolderId;
    final cached = _folderIds[folderPath];
    if (cached != null) return cached;
    final parent = p.dirname(folderPath);
    final name = p.basename(folderPath);
    final parentId = await _resolveFolder(parent);
    if (parentId == null) return null;
    final child = await _findChild(parentId, name, folder: true);
    if (child == null) return null;
    _folderIds[folderPath] = child.id!;
    return child.id!;
  }

  Future<String> _ensureFolderPath(String folderPath) async {
    if (folderPath == '' || folderPath == '.') {
      return _rootFolderId ?? await _ensureRootFolder();
    }
    final resolved = await _resolveFolder(folderPath);
    if (resolved != null) return resolved;
    final parent = p.dirname(folderPath);
    final name = p.basename(folderPath);
    final parentId = await _ensureFolderPath(parent);
    final id = await _createFolder(name, parentId);
    _folderIds[folderPath] = id;
    return id;
  }

  Future<String> _ensureRootFolder() async {
    final existing = await _findChild(appDataFolder, appRootFolderName,
        folder: true);
    if (existing != null) {
      final id = existing.id!;
      _folderIds[''] = id;
      _rootFolderId = id;
      return id;
    }
    final id = await _createFolder(appRootFolderName, appDataFolder);
    _folderIds[''] = id;
    _rootFolderId = id;
    return id;
  }

  Future<drive.File?> _findChild(
    String parentId,
    String name, {
    bool folder = false,
  }) async {
    final mimeTypeClause = folder ? " and mimeType='$folderMimeType'" : '';
    final escaped = name.replaceAll("'", "\\'");
    final result = await _drive.files.list(
      spaces: appDataFolder,
      q: "'$parentId' in parents and name='$escaped' and trashed=false"
          '$mimeTypeClause',
      pageSize: 10,
      orderBy: 'createdTime',
      $fields: 'files(id,name,mimeType,createdTime,trashed)',
    );
    final files = result.files ?? const [];
    if (files.isEmpty) return null;
    return files.first;
  }

  Stream<drive.File> _listFolder(String parentId) async* {
    String? pageToken;
    do {
      final result = await _drive.files.list(
        spaces: appDataFolder,
        q: "'$parentId' in parents and trashed=false",
        pageSize: 1000,
        orderBy: 'name',
        pageToken: pageToken,
        $fields: 'nextPageToken,files(id,name,mimeType)',
      );
      for (final file in result.files ?? <drive.File>[]) {
        yield file;
      }
      pageToken = result.nextPageToken;
    } while (pageToken != null);
  }

  Future<String> _createFolder(String name, String parentId) async {
    final file = await _drive.files.create(
      drive.File(name: name, mimeType: folderMimeType, parents: [parentId]),
      $fields: 'id',
    );
    return file.id!;
  }

  Future<String> _createFile(
    String parentId,
    String name,
    Uint8List fileData,
    String? mimeType,
    Map<String, String>? appProperties,
  ) async {
    final file = await _drive.files.create(
      drive.File(
        name: name,
        parents: [parentId],
        appProperties: appProperties,
      ),
      uploadMedia: drive.Media(
        Stream.value(fileData),
        fileData.length,
        contentType: mimeType ?? 'application/octet-stream',
      ),
      uploadOptions: drive.UploadOptions.defaultOptions,
      $fields: 'id,appProperties',
    );
    final id = file.id;
    if (id == null) {
      throw Exception('Failed to create file in Google Drive: $name');
    }
    return id;
  }

  Future<void> _updateFile(
    String fileId,
    Uint8List fileData,
    String? mimeType,
    Map<String, String>? appProperties,
  ) async {
    await _drive.files.update(
      drive.File(appProperties: appProperties),
      fileId,
      uploadMedia: drive.Media(
        Stream.value(fileData),
        fileData.length,
        contentType: mimeType ?? 'application/octet-stream',
      ),
      uploadOptions: drive.UploadOptions.defaultOptions,
      $fields: 'id',
    );
  }

  Future<void> _deleteFile(String fileId) async {
    await _drive.files.delete(fileId);
  }

  Future<Uint8List> _downloadFile(String fileId) async {
    final media = await _drive.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class _RejectingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('No Google Drive access token available.');
  }
}