import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/firestore_cloud.dart';



void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreCloud cloud;

  Future<void> setUpCloud() async {
    fakeFirestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'test-user'),
    );
    cloud = FirestoreCloud(firestore: fakeFirestore, auth: auth);
    await cloud.initialize();
    // Wait for initial snapshot to be processed
    await Future<void>.delayed(Duration.zero);
  }

  group('FirestoreCloud', () {
    test('collectionNames returns expected mapping', () async {
      await setUpCloud();
      expect(cloud.collectionNames[Picture], 'pictures');
      expect(cloud.collectionNames[Record], 'records');
      expect(cloud.collectionNames.length, 2);
    });

    test('supportsEvents returns true (inherited from EventfulCloudBase)',
        () async {
      await setUpCloud();
      expect(cloud.supportsEvents, isTrue);
    });

    test('supportsFiles returns false when no storage configured', () async {
      await setUpCloud();
      expect(cloud.supportsFiles, isFalse);
    });

    test('changes stream is broadcast', () async {
      await setUpCloud();
      expect(cloud.changes, isA<Stream<CloudSyncEvent>>());
      expect(cloud.changes.isBroadcast, isTrue);
    });

    group('initialize', () {
      test('throws when there is no authenticated user', () async {
        final auth = MockFirebaseAuth();
        cloud = FirestoreCloud(firestore: fakeFirestore, auth: auth);

        expect(cloud.initialize(), throwsException);
      });

      test('returns composite id of the authenticated user', () async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'test-user'),
        );
        cloud = FirestoreCloud(firestore: fakeFirestore, auth: auth);

        expect(await cloud.initialize(), 'firebase/test-user');
      });
    });

    test('publishEvent emits event on changes stream', () async {
      await setUpCloud();
      final events = <CloudSyncEvent>[];
      cloud.changes.listen(events.add);
      final event = CloudInsertedEvent(
        metadata: CloudMetadata(
          id: '123',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
        collection: 'pictures',
      );
      cloud.publishEvent(event);
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, same(event));
    });

    test('dispose closes changes stream', () async {
      await setUpCloud();
      var done = false;
      cloud.changes.drain().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      cloud.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    group('saveRecord', () {
      test('inserts new record and returns server-assigned metadata',
          () async {
        await setUpCloud();

        final metadata = await cloud.saveRecord('pictures', null, {
          'id': 'source-456',
          'name': 'Test Picture',
        });

        expect(metadata.id, isNotEmpty);
        expect(metadata.createdAt, isNotNull);
        expect(metadata.updatedAt, isNotNull);

        final snapshot = await fakeFirestore
            .collection('pictures')
            .doc(metadata.id)
            .get();
        expect(snapshot.exists, isTrue);
        final data = snapshot.data()!;
        expect(data['data'], {
          'id': 'source-456',
          'name': 'Test Picture',
        });
        expect(data.containsKey('id'), isFalse);
        expect(data.containsKey('createdAt'), isTrue);
        expect(data.containsKey('updatedAt'), isTrue);
      });

      test('upserts with provided metadata and preserves data', () async {
        await setUpCloud();

        final metadata = await cloud.saveRecord(
          'pictures',
          CloudMetadata(
            id: 'my-existing-id',
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
            deletedAt: DateTime(2024, 2, 1),
          ),
          {'id': 'source-789', 'name': 'Updated Picture'},
        );

        expect(metadata.id, 'my-existing-id');
        expect(metadata.createdAt, DateTime(2024, 1, 1));
        expect(metadata.deletedAt, DateTime(2024, 2, 1));

        final snapshot = await fakeFirestore
            .collection('pictures')
            .doc('my-existing-id')
            .get();
        expect(snapshot.exists, isTrue);
        final data = snapshot.data()!;
        expect(data['data'], {
          'id': 'source-789',
          'name': 'Updated Picture',
        });
        expect(data['createdAt'], '2024-01-01T00:00:00.000');
        expect(data['deletedAt'], '2024-02-01T00:00:00.000');
      });
    });

    group('getRecord', () {
      test('returns record with decoded data map', () async {
        await setUpCloud();

        // Pre-seed a document with a data payload
        await fakeFirestore.collection('pictures').doc('test-id').set({
          'data': {
            'id': 'source-111',
            'name': 'Found Picture',
          },
        });

        final result =
            await cloud.getRecord('pictures', 'test-id');

        expect(result, isNotNull);
        expect(result!['id'], 'source-111');
        expect(result['name'], 'Found Picture');
      });

      test('returns null when record not found', () async {
        await setUpCloud();

        final result =
            await cloud.getRecord('pictures', 'nonexistent');

        expect(result, isNull);
      });

      test('returns null when data map is missing', () async {
        await setUpCloud();

        await fakeFirestore.collection('pictures').doc('no-data').set({
          'name': 'No Data',
        });

        final result = await cloud.getRecord('pictures', 'no-data');

        expect(result, isNull);
      });
    });

    group('listRecords', () {
      test('returns metadata built from stored fields', () async {
        await setUpCloud();

        // Pre-seed documents
        await fakeFirestore.collection('pictures').doc('a').set({
          'createdAt': '2024-01-01T00:00:00.000',
          'updatedAt': '2024-01-02T00:00:00.000',
          'data': {'id': 'src-1', 'name': 'Pic 1'},
        });
        await fakeFirestore.collection('pictures').doc('b').set({
          'createdAt': '2024-02-01T00:00:00.000',
          'updatedAt': '2024-02-02T00:00:00.000',
          'deletedAt': '2024-03-01T00:00:00.000',
          'data': {'id': 'src-2', 'name': 'Pic 2'},
        });

        final results = await cloud.listRecords('pictures');

        expect(results.length, 2);
        expect(results[0].id, 'a');
        expect(results[0].createdAt,
            DateTime.parse('2024-01-01T00:00:00.000'));
        expect(results[0].updatedAt,
            DateTime.parse('2024-01-02T00:00:00.000'));
        expect(results[0].deletedAt, isNull);
        expect(results[1].id, 'b');
        expect(results[1].deletedAt,
            DateTime.parse('2024-03-01T00:00:00.000'));
      });
    });

    group('deleteRecord', () {
      test('deletes document for prefixed id', () async {
        await setUpCloud();

        // Pre-seed a document
        await fakeFirestore.collection('pictures').doc('pic-to-delete').set({
          'name': 'To Delete',
        });

        expect(
          (await fakeFirestore.collection('pictures').doc('pic-to-delete').get())
              .exists,
          isTrue,
        );

        await cloud.deleteRecord('pictures', 'pic-to-delete');

        expect(
          (await fakeFirestore.collection('pictures').doc('pic-to-delete').get())
              .exists,
          isFalse,
        );
      });

      test('does nothing for unprefixed id', () async {
        await setUpCloud();

        // Should not throw
        await cloud.deleteRecord('pictures', 'no-prefix');
      });
    });

    group('realtime events', () {
      test('CloudReconnectedEvent is a valid event type', () {
        expect(const CloudReconnectedEvent(), isA<CloudSyncEvent>());
      });

      test('INSERT event publishes CloudInsertedEvent with data', () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Add a document after initial snapshot
        final docRef = await fakeFirestore.collection('pictures').add({
          'createdAt': '2024-01-01T00:00:00.000',
          'updatedAt': '2024-01-02T00:00:00.000',
          'data': {'id': 'src-1', 'name': 'Inserted'},
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.metadata.id, docRef.id);
        expect(event.metadata.createdAt,
            DateTime.parse('2024-01-01T00:00:00.000'));
        expect(event.collection, 'pictures');
        expect(event.data!['id'], 'src-1');
        expect(event.data!['name'], 'Inserted');
      });

      test('INSERT event without data map publishes null data', () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Add a document without a data payload
        final docRef = await fakeFirestore.collection('pictures').add({
          'name': 'No Data',
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.metadata.id, docRef.id);
        expect(event.collection, 'pictures');
        expect(event.data, isNull);
      });

      test('UPDATE event publishes CloudUpdatedEvent with data', () async {
        await setUpCloud();

        // Seed a document first
        final docRef = await fakeFirestore.collection('pictures').add({
          'data': {'id': 'src-3', 'name': 'Original'},
        });

        // Wait for the add to be processed
        await Future<void>.delayed(Duration.zero);

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Update the document
        await docRef.update({
          'data': {'id': 'src-3', 'name': 'Updated'},
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudUpdatedEvent>());

        final event = events.first as CloudUpdatedEvent;
        expect(event.metadata.id, docRef.id);
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'Updated');
      });

      test('DELETE event publishes CloudDeletedEvent with data', () async {
        await setUpCloud();

        // Seed a document first
        final docRef = await fakeFirestore.collection('pictures').add({
          'data': {'id': 'src-4', 'name': 'To Delete'},
        });

        // Wait for the add to be processed
        await Future<void>.delayed(Duration.zero);

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Delete the document
        await docRef.delete();

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudDeletedEvent>());

        final event = events.first as CloudDeletedEvent;
        expect(event.metadata.id, docRef.id);
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'To Delete');
      });

      test('multiple events are published in order', () async {
        await setUpCloud();

        // Seed documents
        final docRef1 = await fakeFirestore.collection('pictures').add({
          'data': {'id': 'src-a', 'name': 'First'},
        });
        final docRef2 = await fakeFirestore.collection('records').add({
          'data': {'id': 'src-b', 'name': 'Second'},
        });

        // Wait for initial adds to be processed
        await Future<void>.delayed(Duration.zero);

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Make changes to both collections
        await docRef1.update({
          'data': {'id': 'src-a', 'name': 'First Updated'},
        });
        await Future<void>.delayed(Duration.zero);
        await docRef2.update({
          'data': {'id': 'src-b', 'name': 'Second Updated'},
        });
        await Future<void>.delayed(Duration.zero);

        // Wait for snapshot listeners to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.length, 2);
        expect(events[0], isA<CloudUpdatedEvent>());
        expect((events[0] as CloudUpdatedEvent).metadata.id, docRef1.id);
        expect(events[1], isA<CloudUpdatedEvent>());
        expect((events[1] as CloudUpdatedEvent).metadata.id, docRef2.id);
      });
    });
  });
}
