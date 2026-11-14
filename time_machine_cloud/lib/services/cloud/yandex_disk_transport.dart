import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;

/// Metadata of a remote Yandex Disk entry as reported by the REST API.
class YandexDiskEntry {
  const YandexDiskEntry({
    required this.name,
    required this.isDir,
    this.size = 0,
    this.eTag = '',
    this.mTime,
  });

  /// Name of the entry, exactly as the app stored it.
  final String name;

  final bool isDir;

  final int size;

  /// Server-side revision tag; empty when the server reports none. Yandex
  /// Disk returns content hashes (sha256/md5) for files, so changes to a
  /// file's content are always visible.
  final String eTag;

  /// Last-modified timestamp, `null` when the server did not report one.
  final DateTime? mTime;
}

/// Thin gateway to the Yandex Disk REST API. Abstract so tests can
/// substitute an in-memory double; the production implementation,
/// [RestYandexDiskTransport], talks to `https://cloud-api.yandex.net`.
///
/// Paths use the `app:/` shortcut, which always resolves to the connected
/// app's own folder regardless of its real (and locale-dependent) name.
abstract class YandexDiskTransport {
  Future<List<YandexDiskEntry>> readDir(String path);

  Future<void> mkdirAll(String path);

  Future<Uint8List> read(String path);

  Future<void> write(String path, Uint8List data);

  Future<void> remove(String path);

  /// The login of the signed-in account (GET /v1/disk → user.login).
  Future<String> currentUserName();
}

/// Talks to the Yandex Disk REST API (`https://cloud-api.yandex.net/v1/disk/`)
/// using `dio`, authorizing every request with
/// `Authorization: OAuth <token>`.
///
/// All paths begin with the `app:/` prefix so Yandex resolves the current
/// app's folder automatically. Directory operations target the `resources`
/// endpoint; file upload/download resolve a signed href first, then transfer
/// the payload in a separate request.
class RestYandexDiskTransport implements YandexDiskTransport {
  RestYandexDiskTransport(String accessToken)
      : _dio = dio.Dio(
          dio.BaseOptions(
            baseUrl: 'https://cloud-api.yandex.net',
            headers: {'authorization': 'OAuth $accessToken'},
          ),
        );

  final dio.Dio _dio;

  @override
  Future<List<YandexDiskEntry>> readDir(String path) async {
    const limit = 1000;
    final entries = <YandexDiskEntry>[];
    for (var offset = 0;; offset += limit) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/disk/resources',
        queryParameters: {'path': path, 'limit': limit, 'offset': offset},
      );
      final embedded = response.data?['_embedded'];
      if (embedded is! Map<String, dynamic>) break;
      final items = embedded['items'];
      if (items is! List) break;
      entries.addAll([
        for (final item in items.cast<Map<String, dynamic>>())
          YandexDiskEntry(
            name: item['name'] as String? ?? '',
            isDir: item['type'] == 'dir',
            size: (item['size'] as num?)?.toInt() ?? 0,
            eTag: (item['sha256'] ?? item['md5'] ?? '') as String? ?? '',
            mTime: _parseDate(item['modified'] ?? item['created']),
          ),
      ]);
      if (items.length < limit) break;
    }
    return entries;
  }

  @override
  Future<void> mkdirAll(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    // 'app:' alone is the app root; Yandex creates it automatically.
    if (segments.length <= 1) return;
    var current = segments.first;
    for (var i = 1; i < segments.length; i++) {
      current = '$current/${segments[i]}';
      await _createFolder(current);
    }
  }

  Future<void> _createFolder(String path) async {
    try {
      await _dio.put<Map<String, dynamic>>(
        '/v1/disk/resources',
        queryParameters: {'path': path},
      );
    } on dio.DioException catch (error) {
      // 409: the folder (or a same-named resource) already exists.
      if (error.response?.statusCode == 409) return;
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/disk/resources/download',
      queryParameters: {'path': path},
    );
    final href = response.data?['href'] as String?;
    if (href == null) {
      throw Exception('Yandex Disk returned no download URL');
    }
    final download = await _dio.get<List<int>>(
      href,
      options: dio.Options(responseType: dio.ResponseType.bytes),
    );
    return Uint8List.fromList(download.data ?? const []);
  }

  @override
  Future<void> write(String path, Uint8List data) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/disk/resources/upload',
      queryParameters: {'path': path, 'overwrite': true},
    );
    final href = response.data?['href'] as String?;
    if (href == null) {
      throw Exception('Yandex Disk returned no upload URL');
    }
    // The uploader URL needs no OAuth token; dio sends the header anyway,
    // which Yandex ignores. Responses 201 and 202 both mean "accepted".
    await _dio.put<void>(
      href,
      data: data,
      options: dio.Options(
        contentType: 'application/octet-stream',
        responseType: dio.ResponseType.plain,
      ),
    );
  }

  @override
  Future<void> remove(String path) async {
    try {
      await _dio.delete<void>(
        '/v1/disk/resources',
        queryParameters: {'path': path, 'permanently': true},
      );
    } on dio.DioException catch (error) {
      // A missing resource is a successful delete.
      if (error.response?.statusCode == 404) return;
      rethrow;
    }
  }

  @override
  Future<String> currentUserName() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/disk');
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

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}