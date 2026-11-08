import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:time_machine_cloud/services/cloud/dropbox_cloud.dart';
import 'package:time_machine_cloud/services/cloud/google_drive_cloud.dart';
import 'package:time_machine_cloud/services/cloud/yandex_disk_cloud.dart';
import 'package:time_machine_cloud/services/cloud_base.dart';
import 'package:time_machine_core/domain/cloud_metadata.dart';

import '../cloud_cache.dart';
import '../server_config.dart';
import 'api_utils.dart';
import 'provider_credentials.dart';

/// Handles the cloud-storage endpoints used by the web build.
class CloudApi {
  CloudApi({
    required ServerConfig settings,
    required this.maxBodyBytes,
    CloudCache? cache,
  }) : cache =
           cache ??
           CloudCache(
             (provider, token, {startPolling = false}) => _createAndInitCloud(
               provider,
               token,
               settings: settings,
               startPolling: startPolling,
             ),
           );

  final int maxBodyBytes;
  final CloudCache cache;

  Future<Response> me(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    return okResponse(await _providerMe(provider, token));
  }

  Future<Response> recordGet(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final collection = request.url.queryParameters['collection'] ?? 'records';
    final id = request.url.queryParameters['id'] ?? '';
    CloudLease? lease;
    try {
      lease = await cache.acquire(provider, token);
      final data = await lease.cloud.getRecord(collection, id);
      return okResponse({'data': data});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> recordList(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final collection = request.url.queryParameters['collection'] ?? 'records';
    CloudLease? lease;
    try {
      lease = await cache.acquire(provider, token);
      final items = await lease.cloud.listRecords(collection);
      return okResponse({'items': items.map((item) => item.toJson()).toList()});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> recordSave(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final collection = body['collection'] as String? ?? 'records';
    final metadata = body['metadata'] as Map<String, dynamic>?;
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    CloudLease? lease;
    try {
      lease = await cache.acquire(provider, token);
      final meta = await lease.cloud.saveRecord(
        collection,
        metadata != null ? CloudMetadata.fromJson(metadata) : null,
        data,
      );
      return okResponse({'metadata': meta.toJson()});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> recordDelete(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final collection = body['collection'] as String? ?? 'records';
    final id = body['id'] as String? ?? '';
    CloudLease? lease;
    try {
      lease = await cache.acquire(provider, token);
      await lease.cloud.deleteRecord(collection, id);
      return okResponse({'ok': true});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> fileUpload(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final name = request.url.queryParameters['name'] ?? 'upload';
    final mimeType = request.url.queryParameters['mimeType'];
    CloudLease? lease;
    try {
      final bodyBytes = await request.read().expand((x) => x).toList();
      if (provider == 'web') return okResponse({'path': ''});
      lease = await cache.acquire(provider, token);
      final path = await lease.cloud.uploadFile(
        name: name,
        fileData: Uint8List.fromList(bodyBytes),
        mimeType: mimeType,
      );
      return okResponse({'path': path});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> fileDownload(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final path = request.url.queryParameters['path'] ?? '';
    CloudLease? lease;
    try {
      if (provider == 'web') {
        return Response.ok(
          [],
          headers: {'content-type': 'application/octet-stream'},
        );
      }
      lease = await cache.acquire(provider, token);
      final bytes = await lease.cloud.downloadFile(path);
      return Response.ok(
        bytes,
        headers: {'content-type': 'application/octet-stream'},
      );
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  Future<Response> fileDelete(Request request) async {
    final token = _extractToken(request);
    if (token == null) return Response.unauthorized('missing token');
    final provider = request.params['provider'] ?? '';
    final body = decodeJsonBody(await readBody(request, maxBodyBytes));
    final path = body['path'] as String? ?? '';
    CloudLease? lease;
    try {
      if (provider == 'web') return okResponse({'ok': true});
      lease = await cache.acquire(provider, token);
      await lease.cloud.deleteFile(path);
      return okResponse({'ok': true});
    } catch (error) {
      return Response(500, body: error.toString());
    } finally {
      lease?.release();
    }
  }

  FutureOr<Response> changes(Request request) {
    final token = _extractToken(request);
    final provider = request.params['provider'] ?? '';
    return webSocketHandler(
      (WebSocketChannel socket, _) async {
        if (token == null) {
          await socket.sink.close();
          return;
        }
        try {
          // The browser's changes socket anchors a cached cloud: it stays
          // initialized and polling until this socket closes, and HTTP
          // requests from the same browser reuse it.
          final lease = await cache.acquire(provider, token, anchor: true);
          print('WS /api/$provider/changes connected');
          StreamSubscription? sub;
          var stopped = false;
          void stop() {
            if (stopped) return;
            stopped = true;
            sub?.cancel();
            print('WS /api/$provider/changes closed');
            lease.release();
          }

          sub = lease.cloud.changes.listen((event) {
            socket.sink.add(
              json.encode({'type': event.runtimeType.toString()}),
            );
          });
          socket.stream.listen((_) {}, onDone: stop, onError: (_) => stop());
        } catch (_) {
          await socket.sink.close();
        }
      },
      // Detect dead browser connections so their cached cloud is released
      // instead of polling forever.
      pingInterval: const Duration(seconds: 30),
    )(request);
  }

  Future<Map<String, dynamic>> _providerMe(
    String provider,
    String token,
  ) async {
    if (provider == 'web') return {'id': '$provider:web'};
    final lease = await cache.acquire(provider, token);
    try {
      return {'id': lease.id};
    } finally {
      lease.release();
    }
  }
}

String? _extractToken(Request request) {
  final auth =
      request.headers['authorization'] ?? request.headers['Authorization'];
  if (auth != null && auth.startsWith('Bearer ')) {
    return auth.substring('Bearer '.length);
  }
  return request.url.queryParameters['access_token'];
}

Future<CloudInit> _createAndInitCloud(
  String provider,
  String token, {
  required ServerConfig settings,
  bool startPolling = false,
}) async {
  CloudBase? cloud;
  try {
    switch (provider) {
      case 'gdrive':
        final created = GoogleDriveCloud(startPolling: startPolling);
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      case 'dropbox':
        final created = DropBoxCloud(
          clientId: providerClientId('dropbox', settings),
          startPolling: startPolling,
        );
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      case 'yandex':
        final created = YandexDiskCloud(
          clientId: providerClientId('yandex', settings),
          startPolling: startPolling,
        );
        cloud = created;
        await created.authenticateWithAccessToken(accessToken: token);
        return CloudInit(created, await created.initialize());
      default:
        throw ArgumentError('unsupported provider');
    }
  } catch (error, stack) {
    print('Failed to initialize $provider: $error\n$stack');
    cloud?.dispose();
    rethrow;
  }
}
