import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:supabase/supabase.dart';
import 'package:time_machine_db/time_machine_db.dart';

import 'cloud_base.dart';

class SupabaseCloud extends EventfulCloudBase {
  static const idColumn = 'id';
  static const sourceIdColumn = '_id';
  static const dateColumn = 'updated_at';
  static const idPrefix = 'supabase/';

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
       _bucketName = bucketName {
    _initRealtime();
  }

  SupabaseCloud.withClient({
    required SupabaseClient client,
    String bucketName = 'time-machine',
  }) : _client = client,
       _bucketName = bucketName {
    _initRealtime();
  }

  static String? stripPrefix(String? prefixed) {
    if (prefixed == null) return null;
    if (prefixed.startsWith(idPrefix)) {
      return prefixed.substring(idPrefix.length);
    }
    return null;
  }

  static String addPrefix(String id) => '$idPrefix$id';

  void _preserveSourceId(Map<String, dynamic> data) {
    if (data.containsKey(idColumn)) {
      data[sourceIdColumn] = data.remove(idColumn);
    }
  }

  void _restoreSourceId(Map<String, dynamic> data) {
    if (data.containsKey(sourceIdColumn)) {
      data[idColumn] = data.remove(sourceIdColumn);
    }
  }

  void _prefixId(Map<String, dynamic> data) {
    if (data.containsKey(idColumn)) {
      data[idColumn] = addPrefix(data[idColumn] as String);
    }
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
        if (newRecord.isNotEmpty) {
          _restoreSourceId(newRecord);
          _prefixId(newRecord);
          final eventId = newRecord[idColumn] as String?;
          if (eventId != null) {
            publishEvent(CloudInsertedEvent(
              id: eventId,
              collection: table,
              data: newRecord,
            ));
          }
        }
        break;
      case PostgresChangeEvent.update:
        if (newRecord.isNotEmpty) {
          _restoreSourceId(newRecord);
          _prefixId(newRecord);
          final eventId = newRecord[idColumn] as String?;
          if (eventId != null) {
            publishEvent(CloudUpdatedEvent(
              id: eventId,
              collection: table,
              data: newRecord,
            ));
          }
        }
        break;
      case PostgresChangeEvent.delete:
        if (oldRecord.isNotEmpty) {
          _restoreSourceId(oldRecord);
          _prefixId(oldRecord);
          final eventId = oldRecord[idColumn] as String?;
          if (eventId != null) {
            publishEvent(CloudDeletedEvent(
              id: eventId,
              collection: table,
              data: oldRecord,
            ));
          }
        }
        break;
      case PostgresChangeEvent.all:
        break;
    }
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
  Future<String> saveRecord(
    String collection,
    String? id,
    Map<String, dynamic> data,
  ) async {
    _preserveSourceId(data);
    data[dateColumn] = data[dateColumn] ?? DateTime.now().toIso8601String();

    final strippedId = stripPrefix(id);
    if (strippedId != null) {
      data[idColumn] = strippedId;
      await _client.from(collection).upsert(data);
      return id!;
    }

    data.remove(idColumn);
    data['created_at'] = data['created_at'] ?? DateTime.now().toIso8601String();
    final response = await _client.from(collection).insert(data).select();
    if (response.isEmpty) {
      throw Exception('Failed to insert record');
    }
    return addPrefix(response.first[idColumn] as String);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final strippedId = stripPrefix(id);
    if (strippedId == null) return null;

    final result = await _client
        .from(collection)
        .select()
        .eq(idColumn, strippedId)
        .maybeSingle();
    if (result == null) return null;

    _restoreSourceId(result);
    _prefixId(result);
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> listRecords(
    String collection, {
    DateTime? since,
  }) async {
    var query = _client.from(collection).select();
    if (since != null) {
      query = query.gte(dateColumn, since.toIso8601String());
    }
    final results = await query.order(dateColumn);
    for (final result in results) {
      _restoreSourceId(result);
      _prefixId(result);
    }
    return results;
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    final strippedId = stripPrefix(id);
    if (strippedId == null) {
      return;
    }
    await _client.from(collection).delete().eq(idColumn, strippedId);
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
