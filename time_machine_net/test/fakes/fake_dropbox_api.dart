import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropbox_api/dropbox_api.dart';

/// In-memory [DropboxApi] double reproducing the behaviour of the REST layer:
/// conflicts and missing resources surface as [HttpException]s whose message
/// contains the status code, exactly like `OAuth2RestResponse.ensureSuccess`.
class FakeDropboxApi implements DropboxApi {
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {'/'};

  String accountEmail = 'user@example.com';
  String accountId = 'account-id';

  final Map<String, int> _revs = {};
  int _revCounter = 0;

  void touch(String path) => _revs[path] = ++_revCounter;

  static String? _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? null : path.substring(0, index);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  List<DropboxFile> children(String folderPath) {
    final result = <DropboxFile>[];
    for (final path in files.keys) {
      if (_parentOf(path) == folderPath && _revs.containsKey(path)) {
        result.add(_fileMetadata(path));
      }
    }
    return result;
  }

  DropboxFile _fileMetadata(String path) {
    final rev = _revs[path] ?? 0;
    return DropboxFile(
      tag: 'file',
      name: _nameOf(path),
      pathLower: path.toLowerCase(),
      pathDisplay: path,
      id: 'id:$path',
      clientModified: DateTime.utc(2024),
      serverModified: DateTime.utc(2024),
      rev: '$rev',
      size: files[path]?.length,
    );
  }

  @override
  Future<Stream<List<int>>> download(String path) async {
    final data = files[path];
    if (data == null) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (path/not_found)',
      );
    }
    return Stream<List<int>>.value(data);
  }

  @override
  Future<DropboxAccount> getCurrentAccount() async {
    return DropboxAccount(
      accountId: accountId,
      email: accountEmail,
      name: 'Test User',
      disabled: false,
    );
  }

  @override
  Future<DropboxFolderContents> listFolder(
    String path, {
    int limit = 2000,
  }) async {
    if (!folders.contains(path)) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (path/not_found)',
      );
    }
    return DropboxFolderContents(
      entries: children(path),
      cursor: 'cursor-$path',
      hasMore: false,
    );
  }

  @override
  Future<DropboxFolderContents> listFolderContinue(String cursor) async {
    return DropboxFolderContents(entries: [], cursor: cursor, hasMore: false);
  }

  @override
  Future<DropboxFolder> createFolder(String path) async {
    if (folders.contains(path) || files.containsKey(path)) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (to/conflict)',
      );
    }
    folders.add(path);
    return DropboxFolder(
      id: 'id:$path',
      name: _nameOf(path),
      pathLower: path.toLowerCase(),
      pathDisplay: path,
    );
  }

  @override
  Future<DropboxFile> upload(
    String path,
    Stream<List<int>> dataStream, {
    String mode = 'add',
    bool autorename = true,
  }) async {
    if (!folders.contains(_parentOf(path) ?? '/')) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (parent_lookup/not_found)',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in dataStream) {
      builder.add(chunk);
    }
    files[path] = builder.takeBytes();
    touch(path);
    return _fileMetadata(path);
  }

  @override
  Future<void> delete(String path) async {
    final removed = files.remove(path) != null;
    final removedFolder = folders.remove(path);
    if (!removed && !removedFolder) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (path_lookup/not_found)',
      );
    }
    if (removedFolder) {
      files.removeWhere((key, _) => key.startsWith('$path/'));
      folders.removeWhere((folder) => folder.startsWith('$path/'));
    }
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    await copy(fromPath, toPath);
    await delete(fromPath);
  }

  @override
  Future<void> copy(String fromPath, String toPath) async {
    final data = files[fromPath];
    if (data == null) {
      throw const HttpException(
        'HTTP request failed, statusCode=409 (from_lookup/not_found)',
      );
    }
    files[toPath] = data;
    touch(toPath);
  }
}
