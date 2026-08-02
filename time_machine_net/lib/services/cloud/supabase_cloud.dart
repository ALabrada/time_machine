import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:supabase/supabase.dart';
import 'package:time_machine_db/time_machine_db.dart';

import 'cloud_base.dart';

class SupabaseCloud extends EventfulCloudBase {
  static const idColumn = 'id';

  final SupabaseClient _client;
  final String _bucketName;
  final List<RealtimeChannel> _realtimeChannels = [];
  bool _realtimeSubscribed = false;

  @override
  bool get supportsFiles => true;

  @override
  Map<Type, String> get collectionNames => const {
    Picture: 'pictures',
    Record: 'records',
  };

  SupabaseCloud({
    required String supabaseUrl,
    required String supabaseKey,
    String bucketName = 'time-machine',
  }) : _client = SupabaseClient(supabaseUrl, supabaseKey),
       _bucketName = bucketName;

  SupabaseCloud.withClient({
    required SupabaseClient client,
    String bucketName = 'time-machine',
  }) : _client = client,
       _bucketName = bucketName;

  @override
  Future<String> initialize() async {
    var session = _client.auth.currentSession;
    if (session != null && session.isExpired) {
      try {
        session = (await _client.auth.refreshSession()).session;
      } catch (_) {
        session = null;
      }
    }
    final user = session?.user;
    if (user == null) {
      throw Exception('No Supabase session available. Sign in first.');
    }
    _initRealtime();
    return 'supabase/${user.id}';
  }

  void _initRealtime() {
    if (_realtimeSubscribed) return;
    _realtimeSubscribed = true;

    for (final table in collectionNames.values) {
      final channel = _client.channel('supabase-cloud:$table');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) => handlePostgresChange(payload, table),
      );
      _realtimeChannels.add(channel);
      channel.subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          publishEvent(const CloudReconnectedEvent());
        }
      });
    }
  }

  @visibleForTesting
  void handlePostgresChange(PostgresChangePayload payload, String table) {
    final newRecord = Map<String, dynamic>.from(payload.newRecord);
    final oldRecord = Map<String, dynamic>.from(payload.oldRecord);

    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        final eventId = newRecord[idColumn] as String?;
        if (eventId != null) {
          publishEvent(CloudInsertedEvent(
            metadata: metadataFromData(eventId, newRecord),
            collection: table,
            data: _decodeData(newRecord),
          ));
        }
        break;
      case PostgresChangeEvent.update:
        final eventId = newRecord[idColumn] as String?;
        if (eventId != null) {
          publishEvent(CloudUpdatedEvent(
            metadata: metadataFromData(eventId, newRecord),
            collection: table,
            data: _decodeData(newRecord),
          ));
        }
        break;
      case PostgresChangeEvent.delete:
        final eventId = oldRecord[idColumn] as String?;
        if (eventId != null) {
          publishEvent(CloudDeletedEvent(
            metadata: metadataFromData(eventId, oldRecord),
            collection: table,
            data: _decodeData(oldRecord),
          ));
        }
        break;
      case PostgresChangeEvent.all:
        break;
    }
  }

  Map<String, dynamic>? _decodeData(Map<String, dynamic> row) {
    final data = row['data'];
    if (data is String && data.isNotEmpty) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }

  Future<AuthResponse> authenticate(String email, String password) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signInAnonymously() {
    return _client.auth.signInAnonymously();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  bool get isAuthenticated => _client.auth.currentSession != null;

  @override
  void dispose() {
    for (final channel in _realtimeChannels) {
      unawaited(channel.unsubscribe());
    }
    _realtimeChannels.clear();
    unawaited(_client.dispose());
    super.dispose();
  }

  @override
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) async {
    final now = DateTime.now();
    final row = <String, dynamic>{
      'createdAt': metadata?.createdAt.toIso8601String() ?? now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': metadata?.deletedAt?.toIso8601String(),
      'data': jsonEncode(data),
    };

    if (metadata != null) {
      row[idColumn] = metadata.id;
      await _client.from(collection).upsert(row);
      return CloudMetadata(
        id: metadata.id,
        createdAt: metadata.createdAt,
        updatedAt: now,
        deletedAt: metadata.deletedAt,
      );
    }

    final response = await _client.from(collection).insert(row).select();
    if (response.isEmpty) {
      throw Exception('Failed to insert record');
    }
    return metadataFromData(response.first[idColumn] as String, response.first);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final result = await _client
        .from(collection)
        .select()
        .eq(idColumn, id)
        .maybeSingle();
    if (result == null) return null;

    return _decodeData(result);
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection) async {
    final results = await _client.from(collection).select();
    return [
      for (final result in results)
        metadataFromData(result[idColumn] as String, result),
    ];
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    await _client.from(collection).delete().eq(idColumn, id);
  }

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) async {
    await _client.storage.from(_bucketName).uploadBinary(
      name,
      fileData,
      fileOptions: mimeType != null
          ? FileOptions(contentType: mimeType)
          : const FileOptions(),
    );
    return name;
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    return await _client.storage.from(_bucketName).download(path);
  }

  @override
  Future<void> deleteFile(String path) async {
    await _client.storage.from(_bucketName).remove([path]);
  }
}
