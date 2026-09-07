import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// In-memory WebDAV server double reproducing the HTTP behaviour of a
/// Nextcloud instance for the `nextcloud` package: folders are created with
/// MKCOL (405 when they already exist), files are written with PUT, listed
/// with PROPFIND (multistatus XML, `Depth: 1`), read with GET, removed with
/// DELETE (404 when missing) and ETags change on every write so the cloud can
/// detect remote updates by polling.
class FakeNextcloudServer extends http.BaseClient {
  final Map<String, Uint8List> files = {};
  final Set<String> folders = {'TimeMachine'};

  /// The login the server answers to. When either credential field is set,
  /// requested requests must carry a matching `Authorization` header.
  String loginName = 'user';

  /// Valid Bearer token (app password). When non-null, requests are only
  /// accepted if they carry this token as `Authorization: Bearer ...`, or
  /// match [accountPassword] via HTTP Basic.
  String? appPassword;

  /// Valid account password. When non-null, `Authorization: Basic` requests
  /// are only accepted if they decode to `loginName:[accountPassword]`.
  String? accountPassword;

  /// The `Authorization` header of every received request, in order.
  final List<String> requestedAuthorizations = [];

  final Map<String, String> _etags = {};
  int _etagCounter = 0;

  String etagOf(String path) {
    final etag = _etags[path];
    return etag ?? '';
  }

  /// Simulates a remote write to [path] by bumping its ETag.
  void touch(String path) => _etags[path] = _nextEtag();

  void createFolder(String folder) => folders.add(folder);

  void addFile(String path, Uint8List data) {
    files[path] = data;
    _etags[path] = _nextEtag();
  }

  void removePath(String path) {
    if (folders.remove(path)) {
      _etags.remove(path);
    }
    files.remove(path);
    _etags.remove(path);
  }

  String _nextEtag() => '"etag-${++_etagCounter}"';

  static String? _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? null : path.substring(0, index);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedAuthorizations.add(request.headers['Authorization'] ?? '');
    if (!_authorized(request)) {
      return _response(401);
    }
    final url = request.url;
    final segments = url.pathSegments;
    final prefix = segments.indexOf('remote.php');
    final appPath = prefix == -1
        ? ''
        : Uri.decodeComponent(segments.sublist(prefix + 2).join('/'));

    switch (request.method) {
      case 'PROPFIND':
        return _propfind(appPath, request.headers['depth']);
      case 'MKCOL':
        return _mkcol(appPath);
      case 'PUT':
        final body = await _bodyBytes(request);
        return _put(appPath, body);
      case 'DELETE':
        return _delete(appPath);
      case 'GET':
        return _get(appPath);
      default:
        return _response(405, body: 'Method not allowed');
    }
  }

  Future<http.StreamedResponse> _propfind(String path, String? depth) async {
    final isFolder = folders.contains(path);
    final isFile = files.containsKey(path);
    if (!isFolder && !isFile) {
      return _response(404);
    }

    final responses = <String>[];
    responses.add(_folderXml(path));

    if (isFolder && depth == '1') {
      for (final folder in folders) {
        if (folder == path) continue;
        if (_parentOf(folder) == path) {
          responses.add(_folderXml(folder));
        }
      }
      for (final filePath in files.keys) {
        if (_parentOf(filePath) == path) {
          responses.add(_fileXml(filePath));
        }
      }
    }

    final xml = '<?xml version="1.0"?>'
        '<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
        '${responses.join()}</d:multistatus>';
    return _response(207, body: xml);
  }

  String _folderXml(String path) {
    final href = Uri.encodeComponent(path);
    return '<d:response>'
        '<d:href>/remote.php/webdav/$href/</d:href>'
        '<d:propstat>'
        '<d:prop>'
        '<d:resourcetype><d:collection/></d:resourcetype>'
        '<d:getetag>${_etags[path] ?? ''}</d:getetag>'
        '</d:prop>'
        '<d:status>HTTP/1.1 200 OK</d:status>'
        '</d:propstat>'
        '</d:response>';
  }

  String _fileXml(String path) {
    final href = Uri.encodeComponent(path);
    final data = files[path];
    return '<d:response>'
        '<d:href>/remote.php/webdav/$href</d:href>'
        '<d:propstat>'
        '<d:prop>'
        '<d:getcontentlength>${data?.length ?? 0}</d:getcontentlength>'
        '<d:getcontenttype>application/octet-stream</d:getcontenttype>'
        '<d:resourcetype/>'
        '<d:getetag>${_etags[path] ?? ''}</d:getetag>'
        '</d:prop>'
        '<d:status>HTTP/1.1 200 OK</d:status>'
        '</d:propstat>'
        '</d:response>';
  }

  Future<http.StreamedResponse> _mkcol(String path) async {
    final parent = _parentOf(path);
    final parentExists = parent == null || folders.contains(parent) || files.containsKey(parent);
    if (!parentExists || folders.contains(path)) {
      return _response(405);
    }
    folders.add(path);
    return _response(201);
  }

  Future<http.StreamedResponse> _put(String path, Uint8List body) async {
    files[path] = body;
    _etags[path] = _nextEtag();
    return _response(201);
  }

  Future<http.StreamedResponse> _delete(String path) async {
    final isFolder = folders.contains(path);
    final isFile = files.containsKey(path);
    if (!isFolder && !isFile) {
      return _response(404);
    }
    if (isFolder) {
      final prefix = '$path/';
      folders.remove(path);
      folders.removeWhere((f) => f.startsWith(prefix));
      for (final f in files.keys.where((f) => f.startsWith(prefix)).toList()) {
        files.remove(f);
      }
    } else {
      files.remove(path);
    }
    for (final f in _etags.keys.where((f) => f == path || f.startsWith('$path/')).toList()) {
      _etags.remove(f);
    }
    return _response(204);
  }

  Future<http.StreamedResponse> _get(String path) async {
    final data = files[path];
    if (data == null) {
      return _response(404);
    }
    return _response(200, bytes: data);
  }

  bool _authorized(http.BaseRequest request) {
    final validToken = appPassword;
    final validPassword = accountPassword;
    if (validToken == null && validPassword == null) {
      return true;
    }
    final auth = request.headers['Authorization'];
    if (auth == null) {
      return false;
    }
    if (auth.startsWith('Bearer ')) {
      return validToken != null && auth.substring('Bearer '.length) == validToken;
    }
    if (auth.startsWith('Basic ')) {
      if (validPassword == null) {
        return false;
      }
      final decoded = utf8.decode(base64Decode(auth.substring('Basic '.length)));
      final separator = decoded.indexOf(':');
      return separator != -1 &&
          decoded.substring(0, separator) == loginName &&
          decoded.substring(separator + 1) == validPassword;
    }
    return false;
  }

  static Future<Uint8List> _bodyBytes(http.BaseRequest request) async {
    if (request is http.Request && request.bodyBytes.isNotEmpty) {
      return request.bodyBytes;
    }
    final bytes = BytesBuilder(copy: false);
    await request.finalize().listen(bytes.add).asFuture<void>();
    return bytes.takeBytes();
  }

  static http.StreamedResponse _response(
    int status, {
    String? body,
    Uint8List? bytes,
  }) {
    final payload = bytes ?? Uint8List.fromList(utf8.encode(body ?? ''));
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      status,
      contentLength: payload.length,
    );
  }
}