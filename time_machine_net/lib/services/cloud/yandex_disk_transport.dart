import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:webdav_client/webdav_client.dart' as webdav;

/// Metadata of a remote Yandex Disk entry as reported by a WebDAV PROPFIND.
class YandexDiskEntry {
  const YandexDiskEntry({
    required this.name,
    required this.isDir,
    this.size = 0,
    this.eTag = '',
    this.mTime,
  });

  /// URL-decoded name of the entry, exactly as the app stored it.
  final String name;

  final bool isDir;

  final int size;

  /// Server-side revision tag; empty when the server reports none (Yandex
  /// Disk sometimes omits `getetag` from directory listings).
  final String eTag;

  /// Last-modified timestamp, `null` when the server did not report one.
  final DateTime? mTime;
}

/// Thin gateway to the Yandex Disk WebDAV endpoint. Abstract so tests can
/// substitute an in-memory double; the production implementation,
/// [WebDavYandexDiskTransport], wraps the `webdav_client` package.
abstract class YandexDiskTransport {
  Future<List<YandexDiskEntry>> readDir(String path);

  Future<void> mkdirAll(String path);

  Future<Uint8List> read(String path);

  Future<void> write(String path, Uint8List data);

  Future<void> remove(String path);

  /// The login of the signed-in account. Kept separate from the WebDAV
  /// traffic because Yandex's WebDAV endpoint has no account endpoint; the
  /// login comes from the backing REST API (GET /v1/disk → user.login).
  Future<String> currentUserName();
}

/// Talks to the Yandex Disk WebDAV API (`https://webdav.yandex.ru/`) using
/// the third-party `webdav_client` package, authorizing every request with
/// `Authorization: OAuth <token>`.
class WebDavYandexDiskTransport implements YandexDiskTransport {
  WebDavYandexDiskTransport(String accessToken)
      : _accessToken = accessToken {
    _client = webdav.newClient('https://webdav.yandex.ru/');
    _client!.setHeaders({'authorization': 'OAuth $accessToken'});
  }

  static const _diskApiBase = 'https://cloud-api.yandex.net';

  final String _accessToken;
  webdav.Client? _client;

  webdav.Client _requireClient() {
    final client = _client;
    if (client == null) {
      throw Exception('Yandex Disk transport is not connected');
    }
    return client;
  }

  /// Percent-encodes every path segment. The WebDAV server stores the
  /// *decoded* resource name, so both already-encoded record ids (safe
  /// characters pass through unchanged) and raw user file names (spaces and
  /// non-ASCII characters) keep whatever spelling [FileCloudBase] passed in.
  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  @override
  Future<List<YandexDiskEntry>> readDir(String path) async {
    final entries = await _requireClient().readDir(_encodePath(path));
    return [
      for (final entry in entries)
        YandexDiskEntry(
          name: entry.name ?? '',
          isDir: entry.isDir ?? false,
          size: entry.size ?? 0,
          eTag: entry.eTag ?? '',
          mTime: entry.mTime,
        ),
    ];
  }

  @override
  Future<void> mkdirAll(String path) =>
      _requireClient().mkdirAll(_encodePath(path));

  @override
  Future<Uint8List> read(String path) async =>
      Uint8List.fromList(await _requireClient().read(_encodePath(path)));

  @override
  Future<void> write(String path, Uint8List data) =>
      _requireClient().write(_encodePath(path), data);

  @override
  Future<void> remove(String path) =>
      _requireClient().remove(_encodePath(path));

  @override
  Future<String> currentUserName() async {
    final response = await dio.Dio(dio.BaseOptions(baseUrl: _diskApiBase)).get(
      '/v1/disk',
      options: dio.Options(
        headers: {'authorization': 'OAuth $_accessToken'},
      ),
    );
    final user = response.data?['user'];
    if (user is! Map<String, dynamic>) {
      throw Exception('Yandex Disk returned no account information');
    }
    final login = user['login'];
    if (login is! String || login.isEmpty) {
      throw Exception('Yandex Disk returned no account login');
    }
    return login;
  }
}