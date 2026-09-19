import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:time_machine_net/services/cloud/yandex_disk_transport.dart';

/// In-memory [YandexDiskTransport] double reproducing the behaviour of the
/// REST transport: missing files surface as exceptions and deletes are
/// idempotent.
class FakeYandexTransport implements YandexDiskTransport {
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {'/'};

  String currentUser = 'user@example.com';

  final Map<String, int> _revs = {};
  int _revCounter = 0;

  /// When `true`, directory listings carry a revision (`eTag`, the default
  /// WebDAV behaviour). Set to `false` to reproduce servers that omit
  /// `getetag`, which forces the size+mtime fallback fingerprint.
  bool emitEtags = true;

  /// Static timestamp of every entry, so the fallback revision only depends
  /// on the file size (mirrors a server that updates content length).
  final DateTime entryTime = DateTime.utc(2024, 1, 2);

  void touch(String path) => _revs[path] = ++_revCounter;

  static String? _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? null : path.substring(0, index);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  List<YandexDiskEntry> children(String folderPath) {
    final result = <YandexDiskEntry>[];
    for (final path in files.keys) {
      if (_parentOf(path) == folderPath && _revs.containsKey(path)) {
        result.add(_fileMetadata(path));
      }
    }
    return result;
  }

  YandexDiskEntry _fileMetadata(String path) {
    final rev = _revs[path] ?? 0;
    return YandexDiskEntry(
      name: _nameOf(path),
      isDir: false,
      size: files[path]?.length ?? 0,
      eTag: emitEtags ? 'etag-$rev' : '',
      mTime: entryTime,
    );
  }

  @override
  Future<List<YandexDiskEntry>> readDir(String path) async {
    if (!folders.contains(path)) {
      throw const HttpException('HTTP request failed, statusCode=404');
    }
    return children(path);
  }

  @override
  Future<void> mkdirAll(String path) async {
    // Creates the folder and every missing parent, and tolerates folders
    // that already exist. Paths use the `app:` prefix, which the transport
    // resolves to the app root ('app:' alone needs no request).
    final segments = path.split('/');
    var sub = '';
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      sub = sub.isEmpty ? segment : '$sub/$segment';
      folders.add(sub);
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    final data = files[path];
    if (data == null) {
      throw const HttpException('HTTP request failed, statusCode=404');
    }
    return data;
  }

  @override
  Future<void> write(String path, Uint8List data) async {
    final parent = _parentOf(path) ?? '/';
    if (!folders.contains(parent)) {
      await mkdirAll(parent);
    }
    files[path] = data;
    touch(path);
  }

  @override
  Future<void> remove(String path) async {
    final removedFile = files.remove(path) != null;
    final removedFolder = folders.remove(path);
    if (removedFile || removedFolder || _revs.containsKey(path)) {
      _revs.remove(path);
      if (removedFolder) {
        files.removeWhere((key, _) => key.startsWith('$path/'));
        folders.removeWhere((folder) => folder.startsWith('$path/'));
        _revs.removeWhere((key, _) => key.startsWith('$path/'));
      }
      return;
    }
    // A missing resource is a successful delete on WebDAV.
  }

  @override
  Future<String> currentUserName() async => currentUser;
}