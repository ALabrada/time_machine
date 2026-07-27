import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:meta/meta.dart';
import 'package:time_machine_db/time_machine_db.dart';

import 'cloud_base.dart';

class FirestoreCloud extends EventfulCloudBase {
  static const idColumn = 'id';
  static const sourceIdColumn = '_id';
  static const dateColumn = 'updated_at';
  static const idPrefix = 'firestore/';

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storage;
  final String _bucketName;
  final List<StreamSubscription<QuerySnapshot>> _subscriptions = [];
  bool _realtimeSubscribed = false;
  bool _initialSnapshotReceived = false;

  @override
  bool get supportsFiles => _storage != null;

  @override
  Map<Type, String> get collectionNames => const {
    Picture: 'pictures',
    Record: 'records',
  };

  FirestoreCloud({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    String bucketName = 'time-machine',
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage,
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

    for (final collection in collectionNames.values) {
      final sub = _firestore
          .collection(collection)
          .snapshots()
          .listen((snapshot) {
        if (!_initialSnapshotReceived) {
          _initialSnapshotReceived = true;
          publishEvent(const CloudReconnectedEvent());
          return;
        }
        for (final change in snapshot.docChanges) {
          _handleDocChange(change, collection);
        }
      });
      _subscriptions.add(sub);
    }
  }

  @visibleForTesting
  void handleDocChange(DocumentChange change, String collection) {
    _handleDocChange(change, collection);
  }

  void _handleDocChange(DocumentChange change, String collection) {
    final data = change.doc.data() as Map<String, dynamic>?;
    if (data == null || data.isEmpty) return;

    final record = Map<String, dynamic>.from(data);
    _restoreSourceId(record);
    if (!record.containsKey(idColumn)) {
      record[idColumn] = change.doc.id;
    }
    _prefixId(record);
    final eventId = record[idColumn] as String?;
    if (eventId == null) return;

    switch (change.type) {
      case DocumentChangeType.added:
        publishEvent(CloudInsertedEvent(
          id: eventId,
          collection: collection,
          data: record,
        ));
      case DocumentChangeType.modified:
        publishEvent(CloudUpdatedEvent(
          id: eventId,
          collection: collection,
          data: record,
        ));
      case DocumentChangeType.removed:
        publishEvent(CloudDeletedEvent(
          id: eventId,
          collection: collection,
          data: record,
        ));
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
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
      await _firestore.collection(collection).doc(strippedId).set(
        data,
        SetOptions(merge: true),
      );
      return id!;
    }

    data.remove(idColumn);
    data['created_at'] = data['created_at'] ?? DateTime.now().toIso8601String();
    final docRef = await _firestore.collection(collection).add(data);
    return addPrefix(docRef.id);
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final strippedId = stripPrefix(id);
    if (strippedId == null) return null;

    final snapshot = await _firestore.collection(collection).doc(strippedId).get();
    if (!snapshot.exists) return null;

    final data = Map<String, dynamic>.from(
      snapshot.data() as Map<String, dynamic>,
    );
    _restoreSourceId(data);
    if (!data.containsKey(idColumn)) {
      data[idColumn] = snapshot.id;
    }
    _prefixId(data);
    return data;
  }

  @override
  Future<List<Map<String, dynamic>>> listRecords(
    String collection, {
    DateTime? since,
  }) async {
    var query = _firestore.collection(collection) as Query;
    if (since != null) {
      query = query.where(
        dateColumn,
        isGreaterThanOrEqualTo: since.toIso8601String(),
      );
    }
    final snapshots = await query.orderBy(dateColumn, descending: false).get();
    final results = snapshots.docs.map((doc) {
      final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>,
      );
      _restoreSourceId(data);
      if (!data.containsKey(idColumn)) {
        data[idColumn] = doc.id;
      }
      _prefixId(data);
      return data;
    }).toList();
    return results;
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    final strippedId = stripPrefix(id);
    if (strippedId == null) return;
    await _firestore.collection(collection).doc(strippedId).delete();
  }

  @override
  Future<String> uploadFile({
    required String name,
    required Uint8List fileData,
    String? mimeType,
  }) async {
    final storage = _storage;
    if (storage == null) {
      throw Exception('Firebase Storage not configured');
    }
    final ref = storage.ref(_bucketName).child(name);
    final metadata = mimeType != null ? SettableMetadata(contentType: mimeType) : null;
    await ref.putData(fileData, metadata);
    return name;
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    final storage = _storage;
    if (storage == null) {
      throw Exception('Firebase Storage not configured');
    }
    final data = await storage.ref(_bucketName).child(path).getData();
    if (data == null) {
      throw Exception('File not found');
    }
    return data;
  }

  @override
  Future<void> deleteFile(String path) async {
    final storage = _storage;
    if (storage == null) {
      throw Exception('Firebase Storage not configured');
    }
    await storage.ref(_bucketName).child(path).delete();
  }
}
