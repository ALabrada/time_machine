import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/services/cloud/supabase_cloud.dart';

const testUrl = 'https://test.supabase.co';
const testKey = 'test-key-12345';
const testBucket = 'test-bucket';

final _authResponse = Response(
  json.encode({
    'external': {
      'apple': false,
      'azure': false,
      'bitbucket': false,
      'discord': false,
      'facebook': false,
      'github': false,
      'gitlab': false,
      'google': false,
      'keycloak': false,
      'linkedin': false,
      'notion': false,
      'oidc': false,
      'google_workspace': false,
      'apple_workspace': false,
      'mfa': false,
      'password': false,
      'phone': false,
      'saml': false,
      'spotify': false,
      'slack': false,
      'twitch': false,
      'twitter': false,
      'workos': false,
      'zoom': false,
    },
    'disable_signup': false,
    'automatic_reconfirmation': false,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<Request> requests;
  late SupabaseCloud cloud;

  Future<void> setUpCloud({
    Future<void> Function(Request req)? assertFn,
    Response Function(Request)? mockFor,
  }) async {
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);

      if (assertFn != null) {
        await assertFn(request);
      }

      final uri = Uri.parse(request.url.toString());

      if (uri.path.endsWith('/auth/v1/settings') &&
          request.method == 'GET') {
        return Response(
          _authResponse.body,
          _authResponse.statusCode,
          headers: _authResponse.headers,
          request: request,
        );
      }

      if (uri.path.contains('/auth/v1/') && request.method == 'POST') {
        if (mockFor != null) {
          return mockFor(request);
        }
        if (uri.path.contains('/logout')) {
          return Response('', 204, request: request);
        }
        return Response(
          json.encode({
            'access_token': 'test-access-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'test-refresh-token',
            'user': {
              'id': 'auth-test-user',
              'email': 'test@example.com',
              'aud': 'authenticated',
              'created_at': '2024-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
              'identities': [],
              'is_anonymous': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }

      if (mockFor != null) {
        return mockFor(request);
      }

      if (request.method == 'GET') {
        return Response(json.encode([]), 200,
            headers: {'content-type': 'application/json'},
            request: request);
      }

      if (request.method == 'POST') {
        return Response(json.encode([{'id': 'new-uuid'}]),
            201,
            headers: {'content-type': 'application/json'},
            request: request);
      }

      if (request.method == 'PATCH') {
        return Response(json.encode([]), 200,
            headers: {'content-type': 'application/json'},
            request: request);
      }

      if (request.method == 'DELETE') {
        return Response(json.encode([]), 200,
            headers: {'content-type': 'application/json'},
            request: request);
      }

      return Response('', 404, request: request);
    });
    final supabase = SupabaseClient(testUrl, testKey, httpClient: client);
    cloud = SupabaseCloud.withClient(
      client: supabase,
      bucketName: testBucket,
    );
  }

  group('SupabaseCloud', () {
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

    test('supportsFiles returns true', () async {
      await setUpCloud();
      expect(cloud.supportsFiles, isTrue);
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
        id: '123',
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
        await setUpCloud(assertFn: (request) async {
          final body = json.decode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          expect(body['_id'], 'source-456');
          expect(body.containsKey('id'), isFalse);
          expect(request.method, 'POST');
          expect(request.url.toString(), contains('/rest/v1/pictures'));
        });

        final id = await cloud.saveRecord('pictures', null, {
          'id': 'source-456',
          'name': 'Test Picture',
        });

        expect(id, 'new-uuid');
      });

      test('upserts when id has prefix and returns prefixed id', () async {
        await setUpCloud(assertFn: (request) async {
          final body = json.decode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          expect(body['id'], 'my-existing-id');
          expect(body['_id'], 'source-789');
          expect(body['name'], 'Updated Picture');
          expect(body.containsKey('created_at'), isFalse);
          expect(request.headers['Prefer'],
              contains('resolution=merge-duplicates'));
        });

        final id = await cloud.saveRecord(
          'pictures',
          'my-existing-id',
          {'id': 'source-789', 'name': 'Updated Picture'},
        );

        expect(id, 'my-existing-id');
      });

      test('upserts when id is not null',
          () async {
        await setUpCloud(assertFn: (request) async {
          final body = json.decode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          expect(body['id'], 'any-id');
          expect(body['_id'], 'source-abc');
          expect(body['name'], 'Local Picture');
          expect(body.containsKey('created_at'), isFalse);
          expect(request.headers['Prefer'],
              contains('resolution=merge-duplicates'));
        });

        final id = await cloud.saveRecord(
          'pictures',
          'any-id',
          {'id': 'source-abc', 'name': 'Local Picture'},
        );

        expect(id, 'any-id');
      });
    });

    group('getRecord', () {
      test('returns record with restored and prefixed id', () async {
        await setUpCloud(
          assertFn: (request) async {
            expect(request.method, 'GET');
            final query =
                Uri.parse(request.url.toString()).queryParameters;
            expect(query['select'], '*');
            expect(query['id'], 'eq.test-id');
          },
          mockFor: (request) {
            final uri = Uri.parse(request.url.toString());
            if (uri.path.contains('/auth/v1/')) {
              return Response(
                _authResponse.body,
                _authResponse.statusCode,
                headers: _authResponse.headers,
                request: request,
              );
            }
            return Response(
              json.encode([
                {
                  'id': 'test-id',
                  '_id': 'source-111',
                  'name': 'Found Picture',
                }
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          },
        );

        final result = await cloud.getRecord('pictures', 'test-id');

        expect(result, isNotNull);
        expect(result!['id'], 'source-111');
        expect(result['name'], 'Found Picture');
        expect(result.containsKey('_id'), isFalse);
      });

      test('returns null when record not found', () async {
        await setUpCloud();

        final result =
            await cloud.getRecord('pictures', 'nonexistent');

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
        await setUpCloud(
          assertFn: (request) async {
            expect(request.method, 'GET');
            expect(request.url.toString(), contains('/rest/v1/pictures'));
          },
          mockFor: (request) {
            final uri = Uri.parse(request.url.toString());
            if (uri.path.contains('/auth/v1/')) {
              return Response(
                _authResponse.body,
                _authResponse.statusCode,
                headers: _authResponse.headers,
                request: request,
              );
            }
            return Response(
              json.encode([
                {'id': 'a', '_id': 'src-1', 'name': 'Pic 1'},
                {'id': 'b', '_id': 'src-2', 'name': 'Pic 2'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          },
        );

        final results = await cloud.listRecords('pictures');

        expect(results.length, 2);
        expect(results[0]['id'], 'src-1');
        expect(results[0]['name'], 'Pic 1');
        expect(results[0].containsKey('_id'), isFalse);
        expect(results[1]['id'], 'src-2');
        expect(results[1]['name'], 'Pic 2');
      });
    });

    group('deleteRecord', () {
      test('sends DELETE request for prefixed id', () async {
        await setUpCloud(assertFn: (request) async {
          expect(request.method, 'DELETE');
          expect(request.url.toString(),
              contains('/rest/v1/pictures?id=eq.pic-to-delete'));
        });

        await cloud.deleteRecord('pictures', 'pic-to-delete');
        expect(requests.any((r) => r.method == 'DELETE'), isTrue);
      });
    });

    group('file operations', () {
      test('uploadFile uploads binary data to storage', () async {
        await setUpCloud(
          assertFn: (request) async {
            expect(request.method, 'POST');
            expect(request.url.toString(),
                contains('/storage/v1/object/$testBucket/'));
          },
          mockFor: (request) {
            final uri = Uri.parse(request.url.toString());
            if (uri.path.contains('/storage/')) {
              return Response(
                json.encode({'Key': 'photos/test.jpg'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return Response('', 404, request: request);
          },
        );

        final result = await cloud.uploadFile(
          name: 'photos/test.jpg',
          fileData: Uint8List.fromList([0, 1, 2, 3]),
          mimeType: 'image/jpeg',
        );

        expect(result, 'photos/test.jpg');
      });

      test('downloadFile downloads binary data from storage', () async {
        final fileBytes = Uint8List.fromList([10, 20, 30, 40]);

        await setUpCloud(
          assertFn: (request) async {
            expect(request.method, 'GET');
            expect(request.url.toString(),
                contains('/storage/v1/object/$testBucket/'));
          },
          mockFor: (request) {
            final uri = Uri.parse(request.url.toString());
            if (uri.path.contains('/storage/')) {
              return Response.bytes(fileBytes, 200,
                  headers: {'content-type': 'image/jpeg'},
                  request: request);
            }
            return Response('', 404, request: request);
          },
        );

        final data = await cloud.downloadFile('photos/test.jpg');

        expect(data, fileBytes);
      });

      test('deleteFile removes file from storage', () async {
        await setUpCloud(
          assertFn: (request) async {
            expect(request.method, 'DELETE');
            expect(request.url.toString(),
                contains('/storage/v1/object/$testBucket'));
          },
          mockFor: (request) {
            final uri = Uri.parse(request.url.toString());
            if (uri.path.contains('/auth/v1/')) {
              return Response(
                _authResponse.body,
                _authResponse.statusCode,
                headers: _authResponse.headers,
                request: request,
              );
            }
            if (request.method == 'DELETE') {
              return Response(
                json.encode([{'name': 'photos/test.jpg'}]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return Response('', 404, request: request);
          },
        );

        await cloud.deleteFile('photos/test.jpg');
        expect(requests.any((r) => r.method == 'DELETE'), isTrue);
      });
    });

    group('error handling', () {
      test('saveRecord throws on failed insert', () async {
        await setUpCloud(mockFor: (request) {
          final uri = Uri.parse(request.url.toString());
          if (uri.path.contains('/auth/v1/')) {
            return Response(
              _authResponse.body,
              _authResponse.statusCode,
              headers: _authResponse.headers,
              request: request,
            );
          }
          return Response(json.encode([]), 201,
              headers: {'content-type': 'application/json'},
              request: request);
        });

        expect(
          () => cloud.saveRecord('pictures', null, {'name': 'Test'}),
          throwsException,
        );
      });

      test('deleteRecord succeeds on non-existent record', () async {
        await setUpCloud(mockFor: (request) {
          final uri = Uri.parse(request.url.toString());
          if (uri.path.contains('/auth/v1/')) {
            return Response(
              _authResponse.body,
              _authResponse.statusCode,
              headers: _authResponse.headers,
              request: request,
            );
          }
          return Response(json.encode([]), 200,
              headers: {'content-type': 'application/json'},
              request: request);
        });

        await cloud.deleteRecord('pictures', 'nonexistent');
        expect(requests.any((r) => r.method == 'DELETE'), isTrue);
      });
    });

    group('authentication', () {
      test('authenticate calls signInWithPassword and returns AuthResponse',
          () async {
        await setUpCloud();

        final result = await cloud.authenticate(
          'test@example.com',
          'password123',
        );

        expect(result, isA<AuthResponse>());
        expect(result.user?.email, 'test@example.com');
        expect(result.session?.accessToken, isNotEmpty);
        expect(cloud.isAuthenticated, isTrue);
      });

      test('signInAnonymously returns anonymous session', () async {
        await setUpCloud();

        final result = await cloud.signInAnonymously();

        expect(result, isA<AuthResponse>());
        expect(result.session?.accessToken, isNotEmpty);
        expect(cloud.isAuthenticated, isTrue);
      });

      test('signOut clears authentication', () async {
        await setUpCloud();

        await cloud.authenticate('test@example.com', 'password123');
        expect(cloud.isAuthenticated, isTrue);

        final tokenReq = requests.firstWhere(
          (r) => r.url.toString().contains('/auth/v1/token'),
        );
        final body = json.decode(utf8.decode(tokenReq.bodyBytes))
            as Map<String, dynamic>;
        expect(body['email'], 'test@example.com');
        expect(body['password'], 'password123');
        expect(Uri.parse(tokenReq.url.toString()).queryParameters['grant_type'],
            'password');

        // signOut sends POST to /auth/v1/logout
        final logoutReqCount = requests.where(
          (r) => r.url.toString().contains('/auth/v1/logout'),
        ).length;
        expect(logoutReqCount, 0);

        await cloud.signOut();

        final logoutRequests = requests.where(
          (r) => r.url.toString().contains('/auth/v1/logout'),
        ).toList();
        expect(logoutRequests.length, logoutReqCount + 1);
        expect(logoutRequests.first.method, 'POST');
        expect(cloud.isAuthenticated, isFalse);
      });

      test('isAuthenticated returns false before sign in', () async {
        await setUpCloud();
        expect(cloud.isAuthenticated, isFalse);
      });
    });

    group('realtime events', () {
      PostgresChangePayload _payload({
        required PostgresChangeEvent eventType,
        Map<String, dynamic> newRecord = const {},
        Map<String, dynamic> oldRecord = const {},
        String table = 'pictures',
      }) {
        return PostgresChangePayload(
          schema: 'public',
          table: table,
          commitTimestamp: DateTime.now(),
          eventType: eventType,
          newRecord: newRecord,
          oldRecord: oldRecord,
          errors: null,
        );
      }

      test('CloudReconnectedEvent is a valid event type', () {
        expect(const CloudReconnectedEvent(), isA<CloudSyncEvent>());
      });

      test('INSERT event publishes CloudInsertedEvent with transformed data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.insert,
            newRecord: {
              'id': 'db-1',
              '_id': 'src-1',
              'name': 'Inserted',
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.id, 'src-1');
        expect(event.collection, 'pictures');
        expect(event.data!['id'], 'src-1');
        expect(event.data!['name'], 'Inserted');
        expect(event.data!.containsKey('_id'), isFalse);
      });

      test('INSERT event with no sourceId uses raw db id as prefixed id',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.insert,
            newRecord: {
              'id': 'db-2',
              'name': 'No Source Id',
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        final event = events.first as CloudInsertedEvent;
        expect(event.id, 'db-2');
        expect(event.data!['id'], 'db-2');
      });

      test('INSERT event with empty newRecord publishes nothing', () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(eventType: PostgresChangeEvent.insert),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
      });

      test('UPDATE event publishes CloudUpdatedEvent with transformed data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'db-3',
              '_id': 'src-3',
              'name': 'Updated',
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudUpdatedEvent>());

        final event = events.first as CloudUpdatedEvent;
        expect(event.id, 'src-3');
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'Updated');
      });

      test('DELETE event publishes CloudDeletedEvent with old record data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.delete,
            oldRecord: {
              'id': 'db-4',
              '_id': 'src-4',
              'name': 'Deleted',
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudDeletedEvent>());

        final event = events.first as CloudDeletedEvent;
        expect(event.id, 'src-4');
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'Deleted');
      });

      test('DELETE event with empty oldRecord publishes nothing', () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(eventType: PostgresChangeEvent.delete),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
      });

      test('multiple events are published in order', () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.insert,
            newRecord: {'id': 'a', '_id': 'src-a', 'name': 'First'},
          ),
          'pictures',
        );

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.update,
            newRecord: {'id': 'b', '_id': 'src-b', 'name': 'Second'},
          ),
          'records',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 2);
        expect(events[0], isA<CloudInsertedEvent>());
        expect((events[0] as CloudInsertedEvent).id, 'src-a');
        expect(events[1], isA<CloudUpdatedEvent>());
        expect((events[1] as CloudUpdatedEvent).id, 'src-b');
      });
    });
  });
}
