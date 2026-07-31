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

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storage;
  final String _bucketName;
  final List<StreamSubscription<QuerySnapshot>> _subscriptions = [];
  bool _realtimeSubscribed = false;
  bool _initialSnapshotReceived = false;

  @override
  String get id => 'firestore';

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

    if (id != null) {
      data[idColumn] = id;
      await _firestore.collection(collection).doc(id).set(
        data,
        SetOptions(merge: true),
      );
      return id;
    }

    data.remove(idColumn);
    final docRef = await _firestore.collection(collection).add(data);
    return docRef.id;
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final snapshot = await _firestore.collection(collection).doc(id).get();
    if (!snapshot.exists) return null;

    final data = Map<String, dynamic>.from(
      snapshot.data() as Map<String, dynamic>,
    );
    _restoreSourceId(data);
    if (!data.containsKey(idColumn)) {
      data[idColumn] = snapshot.id;
    }
    return data;
  }

  @override
  Future<List<Map<String, dynamic>>> listRecords(String collection) async {
    var query = _firestore.collection(collection) as Query;
    final snapshots = await query.get();
    final results = snapshots.docs.map((doc) {
      final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>,
      );
      _restoreSourceId(data);
      if (!data.containsKey(idColumn)) {
        data[idColumn] = doc.id;
      }
      return data;
    }).toList();
    return results;
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    await _firestore.collection(collection).doc(id).delete();
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
