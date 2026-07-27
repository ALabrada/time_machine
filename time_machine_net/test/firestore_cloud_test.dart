import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/firestore_cloud.dart';

const prefix = FirestoreCloud.idPrefix;

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreCloud cloud;

  Future<void> setUpCloud() async {
    fakeFirestore = FakeFirebaseFirestore();
    cloud = FirestoreCloud(firestore: fakeFirestore);
    // Wait for initial snapshot to be processed
    await Future<void>.delayed(Duration.zero);
  }

  group('FirestoreCloud', () {
    test('stripPrefix returns suffix for prefixed id', () {
      expect(FirestoreCloud.stripPrefix('${prefix}abc123'), 'abc123');
      expect(FirestoreCloud.stripPrefix(prefix), '');
    });

    test('stripPrefix returns null for unprefixed id', () {
      expect(FirestoreCloud.stripPrefix('local-id'), isNull);
      expect(FirestoreCloud.stripPrefix(null), isNull);
    });

    test('addPrefix prepends prefix', () {
      expect(FirestoreCloud.addPrefix('abc123'), '${prefix}abc123');
    });

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

    test('publishEvent emits event on changes stream', () async {
      await setUpCloud();
      final events = <CloudSyncEvent>[];
      cloud.changes.listen(events.add);
      final event = CloudInsertedEvent(
        id: '${prefix}123',
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
      test('inserts new record when id is null and returns prefixed id',
          () async {
        await setUpCloud();

        final id = await cloud.saveRecord('pictures', null, {
          'id': 'source-456',
          'name': 'Test Picture',
        });

        expect(id, startsWith(prefix));
        expect(FirestoreCloud.stripPrefix(id), isNotNull);

        final strippedId = FirestoreCloud.stripPrefix(id);
        final snapshot =
            await fakeFirestore.collection('pictures').doc(strippedId).get();
        expect(snapshot.exists, isTrue);
        final data = snapshot.data()!;
        expect(data['_id'], 'source-456');
        expect(data['name'], 'Test Picture');
        expect(data['updated_at'], isNotNull);
        expect(data['created_at'], isNotNull);
        expect(data.containsKey('id'), isFalse);
      });

      test('upserts when id has prefix and returns prefixed id', () async {
        await setUpCloud();

        // Pre-seed a document
        await fakeFirestore.collection('pictures').doc('my-existing-id').set({
          'name': 'Old Name',
        });

        final id = await cloud.saveRecord(
          'pictures',
          '${prefix}my-existing-id',
          {'id': 'source-789', 'name': 'Updated Picture'},
        );

        expect(id, '${prefix}my-existing-id');

        // Verify document was updated
        final snapshot = await fakeFirestore
            .collection('pictures')
            .doc('my-existing-id')
            .get();
        expect(snapshot.exists, isTrue);
        final data = snapshot.data()!;
        expect(data['_id'], 'source-789');
        expect(data['name'], 'Updated Picture');
        expect(data['updated_at'], isNotNull);
        expect(data['id'], 'my-existing-id');
      });

      test('inserts new record when id has no prefix and returns prefixed id',
          () async {
        await setUpCloud();

        final id = await cloud.saveRecord(
          'pictures',
          'unprefixed-local-id',
          {'id': 'source-abc', 'name': 'Local Picture'},
        );

        expect(id, startsWith(prefix));
        expect(FirestoreCloud.stripPrefix(id), isNotNull);

        final strippedId = FirestoreCloud.stripPrefix(id);
        final snapshot =
            await fakeFirestore.collection('pictures').doc(strippedId!).get();
        expect(snapshot.exists, isTrue);
        final data = snapshot.data()!;
        expect(data['_id'], 'source-abc');
        expect(data['name'], 'Local Picture');
        expect(data.containsKey('id'), isFalse);
        expect(data['created_at'], isNotNull);
        expect(data['updated_at'], isNotNull);
      });
    });

    group('getRecord', () {
      test('returns record with restored and prefixed id', () async {
        await setUpCloud();

        // Pre-seed a document with source id
        await fakeFirestore.collection('pictures').doc('test-id').set({
          '_id': 'source-111',
          'name': 'Found Picture',
        });

        final result =
            await cloud.getRecord('pictures', '${prefix}test-id');

        expect(result, isNotNull);
        expect(result!['id'], '${prefix}source-111');
        expect(result['name'], 'Found Picture');
        expect(result.containsKey('_id'), isFalse);
      });

      test('returns null when record not found', () async {
        await setUpCloud();

        final result =
            await cloud.getRecord('pictures', '${prefix}nonexistent');

        expect(result, isNull);
      });

      test('returns null for unprefixed id', () async {
        await setUpCloud();

        final result = await cloud.getRecord('pictures', 'no-prefix');

        expect(result, isNull);
      });
    });

    group('listRecords', () {
      test('returns all records with restored and prefixed ids', () async {
        await setUpCloud();

        // Pre-seed documents
        await fakeFirestore.collection('pictures').doc('a').set({
          '_id': 'src-1',
          'name': 'Pic 1',
          'updated_at': '2024-01-01T00:00:00',
        });
        await fakeFirestore.collection('pictures').doc('b').set({
          '_id': 'src-2',
          'name': 'Pic 2',
          'updated_at': '2024-02-01T00:00:00',
        });

        final results = await cloud.listRecords('pictures');

        expect(results.length, 2);
        expect(results[0]['id'], '${prefix}src-1');
        expect(results[0]['name'], 'Pic 1');
        expect(results[0].containsKey('_id'), isFalse);
        expect(results[1]['id'], '${prefix}src-2');
        expect(results[1]['name'], 'Pic 2');
        expect(results[1].containsKey('_id'), isFalse);
      });

      test('filters by updated_at when since is provided', () async {
        await setUpCloud();

        // Pre-seed documents with different dates
        await fakeFirestore.collection('pictures').doc('old').set({
          '_id': 'src-old',
          'name': 'Old',
          'updated_at': '2023-06-01T00:00:00',
        });
        await fakeFirestore.collection('pictures').doc('new').set({
          '_id': 'src-new',
          'name': 'New',
          'updated_at': '2024-06-01T00:00:00',
        });

        final since = DateTime(2024, 1, 1);
        final results =
            await cloud.listRecords('pictures', since: since);

        expect(results.length, 1);
        expect(results[0]['id'], '${prefix}src-new');
        expect(results[0]['name'], 'New');
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

        await cloud.deleteRecord('pictures', '${prefix}pic-to-delete');

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

      test('INSERT event publishes CloudInsertedEvent with transformed data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Add a document after initial snapshot
        await fakeFirestore.collection('pictures').add({
          '_id': 'src-1',
          'name': 'Inserted',
          'updated_at': '2024-01-01T00:00:00',
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.id, '${prefix}src-1');
        expect(event.collection, 'pictures');
        expect(event.data!['id'], '${prefix}src-1');
        expect(event.data!['name'], 'Inserted');
        expect(event.data!.containsKey('_id'), isFalse);
      });

      test('INSERT event with no sourceId uses raw doc id as prefixed id',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Add a document without a source id
        final docRef = await fakeFirestore.collection('pictures').add({
          'name': 'No Source Id',
          'updated_at': '2024-01-01T00:00:00',
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.id, '$prefix${docRef.id}');
        expect(event.collection, 'pictures');
        expect(event.data!['id'], '$prefix${docRef.id}');
        expect(event.data!['name'], 'No Source Id');
      });

      test('UPDATE event publishes CloudUpdatedEvent with transformed data',
          () async {
        await setUpCloud();

        // Seed a document first
        final docRef = await fakeFirestore.collection('pictures').add({
          '_id': 'src-3',
          'name': 'Original',
          'updated_at': '2024-01-01T00:00:00',
        });

        // Wait for the add to be processed
        await Future<void>.delayed(Duration.zero);

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Update the document
        await docRef.update({
          'name': 'Updated',
          'updated_at': '2024-06-01T00:00:00',
        });

        // Wait for snapshot listener to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<CloudUpdatedEvent>());

        final event = events.first as CloudUpdatedEvent;
        expect(event.id, '${prefix}src-3');
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'Updated');
      });

      test('DELETE event publishes CloudDeletedEvent with data', () async {
        await setUpCloud();

        // Seed a document first
        final docRef = await fakeFirestore.collection('pictures').add({
          '_id': 'src-4',
          'name': 'To Delete',
          'updated_at': '2024-01-01T00:00:00',
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
        expect(event.id, '${prefix}src-4');
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'To Delete');
      });

      test('multiple events are published in order', () async {
        await setUpCloud();

        // Seed documents
        final docRef1 = await fakeFirestore.collection('pictures').add({
          '_id': 'src-a',
          'name': 'First',
          'updated_at': '2024-01-01T00:00:00',
        });
        final docRef2 = await fakeFirestore.collection('records').add({
          '_id': 'src-b',
          'name': 'Second',
          'updated_at': '2024-02-01T00:00:00',
        });

        // Wait for initial adds to be processed
        await Future<void>.delayed(Duration.zero);

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        // Make changes to both collections
        await docRef1.update({'name': 'First Updated'});
        await Future<void>.delayed(Duration.zero);
        await docRef2.update({'name': 'Second Updated'});
        await Future<void>.delayed(Duration.zero);

        // Wait for snapshot listeners to fire
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(events.length, 2);
        expect(events[0], isA<CloudUpdatedEvent>());
        expect((events[0] as CloudUpdatedEvent).id, '${prefix}src-a');
        expect(events[1], isA<CloudUpdatedEvent>());
        expect((events[1] as CloudUpdatedEvent).id, '${prefix}src-b');
      });
    });
  });
}
