import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:meta/meta.dart';
import 'package:time_machine_db/time_machine_db.dart';

import 'cloud_base.dart';

class FirestoreCloud extends EventfulCloudBase {
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

    final payload = data['data'];
    final inner = payload is Map<String, dynamic>
        ? Map<String, dynamic>.from(payload)
        : null;
    final metadata = metadataFromData(change.doc.id, data);

    switch (change.type) {
      case DocumentChangeType.added:
        publishEvent(CloudInsertedEvent(
          metadata: metadata,
          collection: collection,
          data: inner,
        ));
      case DocumentChangeType.modified:
        publishEvent(CloudUpdatedEvent(
          metadata: metadata,
          collection: collection,
          data: inner,
        ));
      case DocumentChangeType.removed:
        publishEvent(CloudDeletedEvent(
          metadata: metadata,
          collection: collection,
          data: inner,
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
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) async {
    final now = DateTime.now();
    final doc = <String, dynamic>{
      'createdAt': metadata?.createdAt.toIso8601String() ?? now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': metadata?.deletedAt?.toIso8601String(),
      'data': data,
    };

    if (metadata != null) {
      await _firestore.collection(collection).doc(metadata.id).set(
        doc,
        SetOptions(merge: true),
      );
      return CloudMetadata(
        id: metadata.id,
        createdAt: metadata.createdAt,
        updatedAt: now,
        deletedAt: metadata.deletedAt,
      );
    }

    final docRef = await _firestore.collection(collection).add(doc);
    return CloudMetadata(
      id: docRef.id,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final snapshot = await _firestore.collection(collection).doc(id).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data();
    if (data == null) return null;
    final payload = data['data'];
    return payload is Map<String, dynamic>
        ? Map<String, dynamic>.from(payload)
        : null;
  }

  @override
  Future<List<CloudMetadata>> listRecords(String collection) async {
    final snapshots = await (_firestore.collection(collection) as Query).get();
    return [
      for (final doc in snapshots.docs)
        metadataFromData(doc.id, doc.data() as Map<String, dynamic>),
    ];
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
