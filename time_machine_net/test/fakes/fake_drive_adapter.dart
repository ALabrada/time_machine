import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const folderMimeType = 'application/vnd.google-apps.folder';
const multipartBoundary = '314159265358979323846';
const appDataFolder = 'appDataFolder';

class DriveFile {
  DriveFile({
    required this.id,
    required this.name,
    required this.parentId,
    required this.mimeType,
    required this.createdTime,
    Uint8List? data,
  }) : data = data ?? Uint8List(0);

  final String id;
  final String name;
  final String parentId;
  final String? mimeType;
  final DateTime createdTime;
  Uint8List data;
}

class MultipartPart {
  MultipartPart({
    required this.contentType,
    required this.data,
  });

  final String? contentType;
  final Uint8List data;
}

/// In-memory simulation of the Google Drive REST API v3 as produced by the
/// `googleapis` package, plus an `oauth2.googleapis.com/token` endpoint used
/// by the `googleapis_auth` flows.
class FakeDriveAdapter {
  FakeDriveAdapter({this.userEmail = 'user@example.com'});

  final String userEmail;
  final Map<String, DriveFile> files = {};
  final List<String> authorizationHeaders = [];
  List<Map<String, dynamic>> changeLog = [];
  int _nextId = 1;
  final int _nextChangeToken = 1;

  /// Authorization codes exchanged for tokens by the mock oauth2 endpoint.
  final List<String> exchangedCodes = [];

  List<DriveFile> children(String parentId) =>
      files.values.where((f) => f.parentId == parentId).toList();

  /// Registers a change entry that will be served by the next
  /// [pollChanges] requests. For an insert/update `removed=false` with a full
  /// file resource; for a deletion `removed=true`.
  void addChange({required String fileId, bool removed = false}) {
    final file = files[fileId];
    changeLog.add({
      'fileId': fileId,
      'removed': removed,
      'time': '2024-05-01T00:00:00.000Z',
      if (!removed && file != null)
        'file': {
          'id': file.id,
          'name': file.name,
          'mimeType': file.mimeType,
          'parents': [file.parentId],
          'createdTime': file.createdTime.toIso8601String(),
          'modifiedTime': file.createdTime.toIso8601String(),
        },
    });
  }

  http.Client client() => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final auth = request.headers['Authorization'];
    if (auth != null) authorizationHeaders.add(auth);

    final uri = request.url;
    final segments = uri.pathSegments;
    final method = request.method.toUpperCase();
    final query = uri.queryParameters;
    final bodyBytes = request.bodyBytes;

    if (uri.host == 'oauth2.googleapis.com' && uri.path == '/token') {
      return _handleToken(method, bodyBytes);
    }
    if (segments.isNotEmpty && segments.first == 'upload') {
      return _handleUpload(segments, method, query, bodyBytes);
    }
    if (segments.isNotEmpty && segments.first == 'drive') {
      return _handleDrive(segments, method, query, bodyBytes);
    }
    return http.Response('Not found', 404, headers: _jsonHeaders);
  }

  Future<http.Response> _handleToken(String method, List<int> bodyBytes) async {
    if (method != 'POST') {
      return http.Response('Method not allowed', 405);
    }
    final form = Uri.splitQueryString(utf8.decode(bodyBytes));
    if (form['grant_type'] == 'refresh_token') {
      if (form['refresh_token'] != 'refresh-token') {
        return http.Response('Invalid refresh token', 400);
      }
      return _json({
        'access_token': 'access-token',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'https://www.googleapis.com/auth/drive.appdata',
      });
    }
    final code = form['code'];
    if (code == null) {
      throw StateError('Token exchange without an authorization code');
    }
    exchangedCodes.add(code);
    return _json({
      'access_token': 'access-token',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'scope': 'https://www.googleapis.com/auth/drive.appdata',
    });
  }

  Future<http.Response> _handleDrive(
    List<String> segments,
    String method,
    Map<String, String> query,
    List<int> bodyBytes,
  ) async {
    if (segments.last == 'about') {
      return _json({'user': {'emailAddress': userEmail}});
    }

    if (segments[1] == 'v3' && segments[2] == 'changes') {
      if (segments.length == 4 && segments[3] == 'startPageToken') {
        return _json({'startPageToken': '$_nextChangeToken'});
      }
      if (segments.length == 3) {
        return _json({
          'nextPageToken':
              '${int.tryParse(query['pageToken'] ?? '1')! + 1}',
          'changes': changeLog,
        });
      }
      return http.Response('UNKNOWN changes path', 404);
    }

    if (segments.length == 3 && segments[1] == 'v3' &&
        segments[2] == 'files') {
      switch (method) {
        case 'GET':
          return _handleFilesQuery(query);
        case 'POST':
          final meta = jsonDecode(
            utf8.decode(bodyBytes),
          ) as Map<String, dynamic>;
          return _create(
            meta['name'] as String,
            meta['parents'] as List,
            folderMimeType,
          );
        default:
          return http.Response('Method not allowed', 405);
      }
    }

    if (segments.length == 4 && segments[2] == 'files') {
      final fileId = segments[3];
      final file = files[fileId];
      switch (method) {
        case 'GET':
          if (query['alt'] == 'media') {
            if (file == null) {
              return http.Response('Not found', 404);
            }
            return http.Response.bytes(
             file.data,
              200,
              headers: {
                'content-type': file.mimeType ?? 'application/octet-stream',
              },
            );
          }
          if (file == null) return http.Response('Not found', 404);
          return _json({
            'id': file.id,
            'name': file.name,
            'mimeType': file.mimeType,
            'parents': [file.parentId],
          });
        case 'DELETE':
          files.remove(fileId);
          return http.Response('', 200);
        default:
          return http.Response('Method not allowed', 405);
      }
    }

    return http.Response('Not found', 404);
  }

  Future<http.Response> _handleFilesQuery(Map<String, String> query) async {
    final q = query['q'] ?? '';
    final quoted = RegExp(r"'((?:\\.|[^'])*)'")
        .allMatches(q)
        .map((m) => m.group(1)!)
        .toList();
    final parentId = quoted.isEmpty ? null : quoted[0];
    final name = quoted.length > 1
        ? quoted[1].replaceAll("\\'", "'")
        : null;
    final folderOnly = q.contains("mimeType='$folderMimeType'");
    final matches = files.values.where((f) {
      if (parentId != null && f.parentId != parentId) return false;
      if (name != null && f.name != name) return false;
      if (folderOnly && f.mimeType != folderMimeType) return false;
      return true;
    }).toList();
    return _json({
      'files': [
        for (final f in matches)
          {
            'id': f.id,
            'name': f.name,
            'mimeType': f.mimeType,
            'parents': [f.parentId],
            'createdTime': f.createdTime.toIso8601String(),
          },
      ],
    });
  }

  Future<http.Response> _handleUpload(
    List<String> segments,
    String method,
    Map<String, String> query,
    List<int> bodyBytes,
  ) async {
    final parts = Multipart.parse(bodyBytes);
    if (parts.length < 2) {
      return http.Response('Bad multipart body', 400);
    }
    final metadata = jsonDecode(utf8.decode(parts[0].data))
        as Map<String, dynamic>;
    final name = (metadata['name'] as String?) ?? '';
    final parents = (metadata['parents'] as List?) ?? const [];
    final content = parts[1];

    if (method == 'POST') {
      return _create(name, parents, content.contentType,
          data: content.data);
    }

    if (method == 'PATCH' && segments.length == 5) {
      final fileId = segments[4];
      final file = files[fileId];
      if (file == null) return http.Response('Not found', 404);
      file.data = content.data;
      return _json({'id': file.id, 'name': file.name});
    }

    return http.Response('Method not allowed', 405);
  }

  http.Response _create(
    String name,
    List<dynamic> parents,
    String? mimeType, {
    List<int> data = const [],
  }) {
    final id = 'file_${_nextId++}';
    files[id] = DriveFile(
      id: id,
      name: name,
      parentId: parents.first as String,
      mimeType: mimeType,
      createdTime: DateTime.utc(2024, 1, 1),
      data: Uint8List.fromList(data),
    );
    return _json({'id': id, 'name': name, 'parents': parents});
  }

  static final _jsonHeaders = {
    'content-type': 'application/json',
  };

  http.Response _json(Map<String, dynamic> body) => http.Response(
        jsonEncode(body),
        200,
        headers: _jsonHeaders,
      );
}

class Multipart {
  static List<MultipartPart> parse(List<int> body) {
    final text = utf8.decode(body, allowMalformed: true);
    final parts = <MultipartPart>[];
    for (final part in text.split('--$multipartBoundary')) {
      if (part == '' || part == '--') continue;
      var content = part.startsWith('\r\n') ? part.substring(2) : part;
      if (content.endsWith('\r\n')) {
        content = content.substring(0, content.length - 2);
      }
      final headerEnd = content.indexOf('\r\n\r\n');
      if (headerEnd < 0) continue;
      final header = content.substring(0, headerEnd);
      final payload = content.substring(headerEnd + 4);
      final contentType = RegExp(r'Content-Type:\s*([^\r\n;]+)',
          caseSensitive: false)
          .firstMatch(header)
          ?.group(1)
          ?.trim();
      if (header.toLowerCase().contains('content-transfer-encoding')) {
        final decoded = base64.decode(
          payload.replaceAll('\r\n', '').replaceAll('\n', ''),
        );
        parts.add(MultipartPart(
          contentType: contentType,
          data: Uint8List.fromList(decoded),
        ));
      } else {
        parts.add(MultipartPart(
          contentType: contentType,
          data: Uint8List.fromList(utf8.encode(payload)),
        ));
      }
    }
    return parts;
  }
}

String childId(FakeDriveAdapter adapter, String parentId, String name) =>
    adapter.children(parentId).firstWhere((f) => f.name == name).id;

String encodeName(String name) => Uri.encodeComponent(name);