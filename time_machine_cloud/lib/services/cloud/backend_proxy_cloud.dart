import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'dart:async';
import 'package:time_machine_cloud/services/cloud_sync_provider.dart';
import 'package:time_machine_core/time_machine_core.dart';

import 'provider_auth.dart';

class BackendProxyCloud implements CloudSyncProvider {
  BackendProxyCloud({
    required this.providerId,
    required this.backendUrl,
    required this.auth,
  })  : _http = http.Client(),
        assert(
          providerId == 'gdrive' || providerId == 'dropbox' || providerId == 'yandex',
          'Unsupported provider: $providerId',
        );

  final String providerId;
  final Uri backendUrl;
  final ProviderAuth auth;
  Map<Type, String> get collectionNames => const {};

  bool get supportsFiles => true;

  final http.Client _http;
  ProviderSession? _session;
  @override
  Future<String> initialize() async {
    try {
      _session = await auth.restore();
    } catch (_) {
      _session = null;
    }
    if (_session == null || _session!.isExpired) {
      _session = await auth.authenticate();
    }
    final me = await _get('/api/$providerId/me');
    final accountId = me['accountId']?.toString() ??
        me['email']?.toString() ??
        me['user']?.toString() ??
        'unknown';
    publishEvent(const CloudReconnectedEvent());
    return '$providerId/$accountId';
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final uri = backendUrl.replace(path: path, queryParameters: query);
    final resp = await _http.get(uri, headers: _headers());
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      final retry = await _http.get(uri, headers: _headers());
      if (retry.statusCode >= 400) throw _error(retry);
      return _decode(retry.body);
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return _decode(resp.body);
  }

  Future<Map<String, dynamic>> _post(String path, dynamic body) async {
    final uri = backendUrl.replace(path: path);
    final resp = await _http.post(uri, headers: _headers(), body: jsonEncode(body));
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      final retry = await _http.post(uri, headers: _headers(), body: jsonEncode(body));
      if (retry.statusCode >= 400) throw _error(retry);
      return _decode(retry.body);
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return _decode(resp.body);
  }

  Future<Uint8List> _getBytes(String path, [Map<String, String>? query]) async {
    final uri = backendUrl.replace(path: path, queryParameters: query);
    final resp = await _http.get(uri, headers: _headers());
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      final retry = await _http.get(uri, headers: _headers());
      if (retry.statusCode >= 400) throw _error(retry);
      return retry.bodyBytes;
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> _postBytes(String path, Uint8List data, Map<String, String> fields) async {
    final uri = backendUrl.replace(path: path);
    final req = http.MultipartRequest('POST', uri);
    _headers().forEach((k, v) => req.headers[k] = v);
    req.fields.addAll(fields);
    req.files.add(http.MultipartFile.fromBytes('file', data, filename: fields['name'] ?? 'file'));
    final streamed = await _http.send(req);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      final req2 = http.MultipartRequest('POST', uri);
      _headers().forEach((k, v) => req2.headers[k] = v);
      req2.fields.addAll(fields);
      req2.files.add(http.MultipartFile.fromBytes('file', data, filename: fields['name'] ?? 'file'));
      final s2 = await _http.send(req2);
      final r2 = await http.Response.fromStream(s2);
      if (r2.statusCode >= 400) throw _error(r2);
      return _decode(r2.body);
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return _decode(resp.body);
  }


  Map<String, String> _headers() {
    final s = _session;
    final h = <String, String>{'Content-Type': 'application/json'};
    if (s != null) h.addAll(s.headers);
    return h;
  }

  Exception _error(http.Response r) => Exception('${r.statusCode}: ${r.body}');

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {'data': body};
    }
  }

  @override
  final _streamController = StreamController<CloudSyncEvent>.broadcast();

  @override
  bool get supportsEvents => true;

  @override
  Stream<CloudSyncEvent> get changes => _streamController.stream;

  void publishEvent(CloudSyncEvent event) {
    _streamController.add(event);
  }

  @override
  Future<void> logout() async {
    _session = null;
    await auth.clear();
  }

  @override
  void dispose() {
    _streamController.close();
    _http.close();
  }

  @override
  Future<CloudMetadata> saveRecord(String collection, CloudMetadata? metadata, Map<String, dynamic> data) async {
    final res = await _post('/api/$providerId/records/save', {
      'collection': collection,
      'metadata': metadata?.toJson(),
      'data': data,
    });
    return CloudMetadata.fromJson(res['metadata'] as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final res = await _get('/api/$providerId/records/get', {'collection': collection, 'id': id});
    return res['data'] as Map<String, dynamic>?;
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection, {DateTime? since}) async {
    final res = await _get('/api/$providerId/records/list', {
      'collection': collection,
      if (since != null) 'since': since.toIso8601String(),
    });
    final items = res['items'] as List<dynamic>? ?? [];
    return items.map((e) => CloudMetadata.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    await _post('/api/$providerId/records/delete', {'collection': collection, 'id': id});
  }

  @override
  Future<String> uploadFile({required String name, required Uint8List fileData, String? mimeType}) async {
    final res = await _postBytes('/api/$providerId/files/upload', fileData, {
      'name': name,
      if (mimeType != null) 'mimeType': mimeType,
    });
    return res['path']?.toString() ?? name;
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    return _getBytes('/api/$providerId/files/download', {'path': path});
  }

  @override
  Future<void> deleteFile(String path) async {
    await _post('/api/$providerId/files/delete', {'path': path});
  }
}
