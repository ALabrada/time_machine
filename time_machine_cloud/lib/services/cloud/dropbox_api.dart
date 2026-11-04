import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Minimal pure-Dart Dropbox REST client.
///
/// `dropbox_api` (and its `oauth2restclient` transport) depends on Flutter,
/// which makes the package unusable from the pure-Dart proxy server. This
/// client only covers the operations the cloud synchronization layer needs.

class DropboxAccount {
  const DropboxAccount({
    required this.accountId,
    required this.email,
    this.name,
    this.disabled = false,
  });

  final String accountId;
  final String email;
  final String? name;
  final bool disabled;
}

class DropboxFile {
  const DropboxFile({
    required this.tag,
    required this.name,
    this.pathLower,
    this.pathDisplay,
    this.id,
    this.clientModified,
    this.serverModified,
    this.rev,
    this.size,
  });

  /// Dropbox entry tag: `file` or `folder`.
  final String tag;
  final String name;
  final String? pathLower;
  final String? pathDisplay;
  final String? id;
  final DateTime? clientModified;
  final DateTime? serverModified;
  final String? rev;
  final int? size;

  bool get isFile => tag == 'file';
}

class DropboxFolder {
  const DropboxFolder({
    required this.id,
    required this.name,
    this.pathLower,
    this.pathDisplay,
  });

  final String id;
  final String name;
  final String? pathLower;
  final String? pathDisplay;
}

class DropboxFolderContents {
  const DropboxFolderContents({
    required this.entries,
    this.cursor,
    this.hasMore = false,
  });

  final List<DropboxFile> entries;
  final String? cursor;
  final bool hasMore;
}

/// The Dropbox operations used by [DropBoxCloud].
///
/// Keeping this an interface lets tests inject an in-memory double without
/// depending on an HTTP transport.
abstract class DropboxApi {
  Future<DropboxAccount> getCurrentAccount();

  Future<DropboxFolderContents> listFolder(String path, {int limit = 2000});

  Future<DropboxFolderContents> listFolderContinue(String cursor);

  Future<DropboxFolder> createFolder(String path);

  Future<DropboxFile> upload(
    String path,
    Stream<List<int>> dataStream, {
    String mode = 'add',
    bool autorename = true,
  });

  Future<void> delete(String path);

  Future<void> move(String fromPath, String toPath);

  Future<void> copy(String fromPath, String toPath);

  Future<Stream<List<int>>> download(String path);

  void setAccessToken(String accessToken) {}
}

/// Pure-Dart Dropbox REST API implementation.
class HttpDropboxApi implements DropboxApi {
  HttpDropboxApi({
    required this.accessToken,
    this.refreshAccessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String accessToken;

  /// Called when the API answers 401 so the caller can renew the token.
  final Future<String?> Function()? refreshAccessToken;

  final http.Client _client;

  static const _apiBase = 'https://api.dropboxapi.com/2';
  static const _contentBase = 'https://content.dropboxapi.com/2';

  @override
  void setAccessToken(String accessToken) {
    this.accessToken = accessToken;
  }

  Map<String, String> _headers({bool json = true}) => {
        'Authorization': 'Bearer $accessToken',
        if (json) 'Content-Type': 'application/json',
      };

  Future<http.Response> _withRetry(
      Future<http.Response> Function() send) async {
    var response = await send();
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken?.call();
      if (refreshed != null && refreshed.isNotEmpty) {
        accessToken = refreshed;
        response = await send();
      }
    }
    _ensureSuccess(response);
    return response;
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP request failed, statusCode=${response.statusCode} '
        '(${response.body})',
      );
    }
  }

  Future<http.Response> _postJson(String path, Object? body) {
    final uri = Uri.parse('$_apiBase$path');
    return _withRetry(
      () => _client.post(
        uri,
        headers: _headers(),
        body: body == null ? 'null' : jsonEncode(body),
      ),
    );
  }

  Future<http.Response> _postContent(
    String path,
    Map<String, Object?> arg,
    List<int> bytes,
  ) {
    final uri = Uri.parse('$_contentBase$path');
    return _withRetry(
      () => _client.post(
        uri,
        headers: {
          ..._headers(json: false),
          'Dropbox-API-Arg': jsonEncode(arg),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      ),
    );
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
  }

  DropboxFile _parseEntry(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return DropboxFile(
      tag: json['.tag'] as String? ?? 'file',
      name: json['name'] as String? ?? '',
      pathLower: json['path_lower'] as String?,
      pathDisplay: json['path_display'] as String?,
      id: json['id'] as String?,
      clientModified: parseDate(json['client_modified']),
      serverModified: parseDate(json['server_modified']),
      rev: json['rev'] as String?,
      size: (json['size'] as num?)?.toInt(),
    );
  }

  DropboxFolderContents _parseFolderContents(Map<String, dynamic> json) {
    final entries = (json['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseEntry)
        .toList();
    return DropboxFolderContents(
      entries: entries,
      cursor: json['cursor'] as String?,
      hasMore: json['has_more'] == true,
    );
  }

  @override
  Future<DropboxAccount> getCurrentAccount() async {
    final response = await _postJson('/users/get_current_account', null);
    final json = _decodeObject(response);
    return DropboxAccount(
      accountId: json['account_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] is Map
          ? (json['name'] as Map)['display_name'] as String?
          : null,
      disabled: json['disabled'] == true,
    );
  }

  @override
  Future<DropboxFolderContents> listFolder(
    String path, {
    int limit = 2000,
  }) async {
    final response = await _postJson('/files/list_folder', {
      'path': path,
      'limit': limit,
    });
    return _parseFolderContents(_decodeObject(response));
  }

  @override
  Future<DropboxFolderContents> listFolderContinue(String cursor) async {
    final response = await _postJson('/files/list_folder/continue', {
      'cursor': cursor,
    });
    return _parseFolderContents(_decodeObject(response));
  }

  @override
  Future<DropboxFolder> createFolder(String path) async {
    final response = await _postJson('/files/create_folder_v2', {
      'path': path,
      'autorename': false,
    });
    final metadata = _decodeObject(response)['metadata'];
    final json =
        metadata is Map<String, dynamic> ? metadata : const <String, dynamic>{};
    return DropboxFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pathLower: json['path_lower'] as String?,
      pathDisplay: json['path_display'] as String?,
    );
  }

  @override
  Future<DropboxFile> upload(
    String path,
    Stream<List<int>> dataStream, {
    String mode = 'add',
    bool autorename = true,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in dataStream) {
      builder.add(chunk);
    }
    final response = await _postContent(
      '/files/upload',
      {
        'path': path,
        'mode': mode,
        'autorename': autorename,
        'mute': false,
      },
      builder.takeBytes(),
    );
    return _parseEntry(_decodeObject(response));
  }

  @override
  Future<void> delete(String path) async {
    await _postJson('/files/delete_v2', {'path': path});
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    await _postJson('/files/move_v2', {
      'from_path': fromPath,
      'to_path': toPath,
      'autorename': false,
    });
  }

  @override
  Future<void> copy(String fromPath, String toPath) async {
    await _postJson('/files/copy_v2', {
      'from_path': fromPath,
      'to_path': toPath,
      'autorename': false,
    });
  }

  @override
  Future<Stream<List<int>>> download(String path) async {
    final response =
        await _postContent('/files/download', {'path': path}, const []);
    return Stream<List<int>>.value(response.bodyBytes);
  }
}
