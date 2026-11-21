import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:time_machine_core/time_machine_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../cloud_base.dart';
import '../cloud_sync_provider.dart';
import 'provider_auth.dart';

class BackendProxyCloud extends CloudBase {
  BackendProxyCloud({
    required this.providerId,
    required this.backendUrl,
    required this.auth,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        assert(
          providerId == 'gdrive' ||
              providerId == 'dropbox' ||
              providerId == 'yandex',
          'Unsupported provider: $providerId',
        );

  final String providerId;
  final Uri backendUrl;
  final ProviderAuth auth;

  @override
  Map<Type, String> get collectionNames =>
      const {Picture: 'pictures', Record: 'records'};

  @override
  bool get supportsFiles => true;

  final http.Client _http;
  ProviderSession? _session;
  String? _userEmail;

  /// Kept open for the lifetime of the browser session. It is the anchor the
  /// proxy uses to cache this client's provider connection between requests.
  WebSocketChannel? _changesChannel;
  StreamSubscription? _changesSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// The signed-in account, once [initialize] reached the provider.
  String? get userEmail => _userEmail;

  /// Runs the browser OAuth flow (or reuses a stored, still valid session).
  Future<void> authenticate() async {
    _session = await auth.restore();
    if (_session == null || _session!.isExpired) {
      _session = await auth.authenticate();
    }
  }

  /// Aborts an interactive sign-in started by [authenticate], if the auth
  /// implementation supports it. Background calls are unaffected because their
  /// [ProviderAuth.restore] work is not cancellable.
  void cancelAuthentication() {
    final interactive = auth;
    if (interactive is CancellableProviderAuth) {
      (interactive as CancellableProviderAuth).cancelPending();
    }
  }

  /// Opens the long-lived changes socket. The proxy caches the provider
  /// connection for as long as this socket stays open, so keeping it alive for
  /// the browser session lets every HTTP request reuse the same cloud.
  void _connectChanges() {
    if (_disposed || _changesChannel != null) return;
    final session = _session;
    if (session == null) return;
    final scheme = switch (backendUrl.scheme) {
      'https' || 'wss' => 'wss',
      _ => 'ws',
    };
    final uri = backendUrl.replace(
      scheme: scheme,
      path: '/api/$providerId/changes',
      queryParameters: {'access_token': session.accessToken},
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _changesChannel = channel;
      _changesSubscription = channel.stream.listen(
        (_) {
          // The proxy only sends the event class name, so a full resync is the
          // safe reaction. CloudSyncService handles UnknownEvent that way.
          if (!_disposed) _streamController.add(const UnknownEvent());
        },
        onDone: _handleChangesClosed,
        onError: (_) => _handleChangesClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleChangesClosed() {
    _changesSubscription?.cancel();
    _changesSubscription = null;
    _changesChannel = null;
    _scheduleReconnect();
  }

  void _restartChanges() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _changesSubscription?.cancel();
    _changesSubscription = null;
    _changesChannel?.sink.close();
    _changesChannel = null;
    _connectChanges();
  }

  void _scheduleReconnect() {
    if (_disposed || _session == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      _connectChanges();
    });
  }

  void _stopChanges() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _changesSubscription?.cancel();
    _changesSubscription = null;
    _changesChannel?.sink.close();
    _changesChannel = null;
  }

  @override
  Future<String> initialize() async {
    var session = _session;
    if (session == null) {
      try {
        session = await auth.restore();
      } catch (_) {
        session = null;
      }
    }
    if (session == null || session.isExpired) {
      // Authentication is an explicit, user-triggered step (see
      // [authenticate]); opening a popup from a background sync would be
      // blocked by the browser anyway.
      throw StateError('Sign-in required for $providerId');
    }
    _session = session;
    // Open the changes socket first: the proxy anchors its cached cloud on
    // this connection, so the /me call below reuses that initialization
    // instead of paying for a second one.
    _connectChanges();
    final me = await _get('/api/$providerId/me');
    final accountId = me['id']?.toString() ??
        me['accountId']?.toString() ??
        me['email']?.toString() ??
        me['user']?.toString() ??
        'unknown';
    _userEmail = accountId.contains('/')
        ? accountId.substring(accountId.indexOf('/') + 1)
        : accountId;
    publishEvent(const CloudReconnectedEvent());
    return '$providerId/$_userEmail';
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final uri = backendUrl.replace(path: path, queryParameters: query);
    final resp = await _http.get(uri, headers: _headers());
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      _restartChanges();
      final retry = await _http.get(uri, headers: _headers());
      if (retry.statusCode >= 400) throw _error(retry);
      return _decode(retry.body);
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return _decode(resp.body);
  }

  Future<Map<String, dynamic>> _post(String path, dynamic body) async {
    final uri = backendUrl.replace(path: path);
    final resp =
        await _http.post(uri, headers: _headers(), body: jsonEncode(body));
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      _restartChanges();
      final retry =
          await _http.post(uri, headers: _headers(), body: jsonEncode(body));
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
      _restartChanges();
      final retry = await _http.get(uri, headers: _headers());
      if (retry.statusCode >= 400) throw _error(retry);
      return retry.bodyBytes;
    }
    if (resp.statusCode >= 400) throw _error(resp);
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> _postBytes(
      String path, Uint8List data, Map<String, String> fields) async {
    final uri = backendUrl.replace(
      path: path,
      queryParameters: {
        if (fields['name'] != null) 'name': fields['name']!,
        if (fields['mimeType'] != null) 'mimeType': fields['mimeType']!,
      },
    );
    final headers = Map<String, String>.from(_headers())
      ..remove('Content-Type')
      ..remove('content-type')
      ..['content-type'] = fields['mimeType'] ?? 'application/octet-stream';
    final resp = await _http.post(uri, headers: headers, body: data);
    if (resp.statusCode == 401) {
      _session = await auth.authenticate();
      _restartChanges();
      final retry = await _http.post(uri, headers: headers, body: data);
      if (retry.statusCode >= 400) throw _error(retry);
      return _decode(retry.body);
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
    _stopChanges();
    await auth.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopChanges();
    _streamController.close();
    _http.close();
  }

  @override
  Future<CloudMetadata> saveRecord(String collection, CloudMetadata? metadata,
      Map<String, dynamic> data) async {
    final res = await _post('/api/$providerId/records/save', {
      'collection': collection,
      'metadata': metadata?.toJson(),
      'data': data,
    });
    return CloudMetadata.fromJson(res['metadata'] as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final res = await _get(
        '/api/$providerId/records/get', {'collection': collection, 'id': id});
    return res['data'] as Map<String, dynamic>?;
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection,
      {DateTime? since}) async {
    final res = await _get('/api/$providerId/records/list', {
      'collection': collection,
      if (since != null) 'since': since.toIso8601String(),
    });
    final items = res['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => CloudMetadata.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    await _post('/api/$providerId/records/delete',
        {'collection': collection, 'id': id});
  }

  @override
  Future<String> uploadFile(
      {required String name,
      required Uint8List fileData,
      String? mimeType}) async {
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
