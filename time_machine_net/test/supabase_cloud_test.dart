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
        await setUpCloud(assertFn: (request) async {
          final body = json.decode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          expect(body.containsKey('id'), isFalse);
          expect(body['createdAt'], isNotEmpty);
          expect(body['updatedAt'], isNotEmpty);
          expect(body['deletedAt'], isNull);
          expect(json.decode(body['data'] as String), {
            'id': 'source-456',
            'name': 'Test Picture',
          });
          expect(request.method, 'POST');
          expect(request.url.toString(), contains('/rest/v1/pictures'));
        });

        final metadata = await cloud.saveRecord('pictures', null, {
          'id': 'source-456',
          'name': 'Test Picture',
        });

        expect(metadata.id, 'new-uuid');
        expect(metadata.createdAt, isNotNull);
        expect(metadata.updatedAt, isNotNull);
      });

      test('upserts with provided metadata and preserves data', () async {
        final createdAt = DateTime(2024, 1, 1);
        final deletedAt = DateTime(2024, 2, 1);
        await setUpCloud(assertFn: (request) async {
          final body = json.decode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          expect(body['id'], 'my-existing-id');
          expect(body['createdAt'], createdAt.toIso8601String());
          expect(body['deletedAt'], deletedAt.toIso8601String());
          expect(json.decode(body['data'] as String), {
            'id': 'source-789',
            'name': 'Updated Picture',
          });
          expect(request.headers['Prefer'],
              contains('resolution=merge-duplicates'));
        });

        final metadata = await cloud.saveRecord(
          'pictures',
          CloudMetadata(
            id: 'my-existing-id',
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: deletedAt,
          ),
          {'id': 'source-789', 'name': 'Updated Picture'},
        );

        expect(metadata.id, 'my-existing-id');
        expect(metadata.createdAt, createdAt);
        expect(metadata.deletedAt, deletedAt);
      });

      test('upsert returns metadata with fresh updatedAt', () async {
        await setUpCloud();
        final before = DateTime.now();

        final metadata = await cloud.saveRecord(
          'pictures',
          CloudMetadata(
            id: 'any-id',
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
          {'id': 'source-abc', 'name': 'Local Picture'},
        );

        final after = DateTime.now();
        expect(metadata.id, 'any-id');
        expect(metadata.createdAt, DateTime(2024, 1, 1));
        expect(metadata.updatedAt.millisecondsSinceEpoch,
            greaterThanOrEqualTo(before.millisecondsSinceEpoch));
        expect(metadata.updatedAt.millisecondsSinceEpoch,
            lessThanOrEqualTo(after.millisecondsSinceEpoch));
      });
    });

    group('getRecord', () {
      test('returns record with decoded data column', () async {
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
                  'data': json.encode({
                    'id': 'source-111',
                    'name': 'Found Picture',
                  }),
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
      });

      test('returns null when record not found', () async {
        await setUpCloud();

        final result =
            await cloud.getRecord('pictures', 'nonexistent');

        expect(result, isNull);
      });

      test('returns null when data column is missing', () async {
        await setUpCloud(
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
                {'id': 'test-id', 'name': 'No Data Column'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          },
        );

        final result = await cloud.getRecord('pictures', 'test-id');

        expect(result, isNull);
      });
    });

    group('listRecords', () {
      test('returns metadata built from persisted columns', () async {
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
                {
                  'id': 'a',
                  'createdAt': '2024-01-01T00:00:00.000',
                  'updatedAt': '2024-01-02T00:00:00.000',
                  'data': json.encode({'id': 'src-1', 'name': 'Pic 1'}),
                },
                {
                  'id': 'b',
                  'createdAt': '2024-02-01T00:00:00.000',
                  'updatedAt': '2024-02-02T00:00:00.000',
                  'deletedAt': '2024-03-01T00:00:00.000',
                  'data': json.encode({'id': 'src-2', 'name': 'Pic 2'}),
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          },
        );

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

      test('initialize throws when there is no authenticated session',
          () async {
        await setUpCloud();
        expect(cloud.initialize(), throwsException);
      });

      test('initialize returns composite id after authenticate', () async {
        await setUpCloud();
        await cloud.authenticate('test@example.com', 'password123');

        expect(await cloud.initialize(), 'supabase/auth-test-user');
      });

      test('initialize returns composite id after signInAnonymously',
          () async {
        await setUpCloud();
        await cloud.signInAnonymously();

        expect(await cloud.initialize(), 'supabase/auth-test-user');
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

      test('INSERT event publishes CloudInsertedEvent with decoded data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.insert,
            newRecord: {
              'id': 'db-1',
              'createdAt': '2024-01-01T00:00:00.000',
              'updatedAt': '2024-01-02T00:00:00.000',
              'data': json.encode({
                'id': 'src-1',
                'name': 'Inserted',
              }),
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudInsertedEvent>());

        final event = events.first as CloudInsertedEvent;
        expect(event.metadata.id, 'db-1');
        expect(event.metadata.createdAt,
            DateTime.parse('2024-01-01T00:00:00.000'));
        expect(event.collection, 'pictures');
        expect(event.data!['id'], 'src-1');
        expect(event.data!['name'], 'Inserted');
      });

      test('INSERT event without data column publishes null data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.insert,
            newRecord: {
              'id': 'db-2',
              'name': 'No Data Column',
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        final event = events.first as CloudInsertedEvent;
        expect(event.metadata.id, 'db-2');
        expect(event.data, isNull);
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

      test('UPDATE event publishes CloudUpdatedEvent with decoded data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'db-3',
              'data': json.encode({
                'id': 'src-3',
                'name': 'Updated',
              }),
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudUpdatedEvent>());

        final event = events.first as CloudUpdatedEvent;
        expect(event.metadata.id, 'db-3');
        expect(event.collection, 'pictures');
        expect(event.data!['name'], 'Updated');
      });

      test('DELETE event publishes CloudDeletedEvent with decoded data',
          () async {
        await setUpCloud();

        final events = <CloudSyncEvent>[];
        cloud.changes.listen(events.add);

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.delete,
            oldRecord: {
              'id': 'db-4',
              'deletedAt': '2024-01-05T00:00:00.000',
              'data': json.encode({
                'id': 'src-4',
                'name': 'Deleted',
              }),
            },
          ),
          'pictures',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(events.first, isA<CloudDeletedEvent>());

        final event = events.first as CloudDeletedEvent;
        expect(event.metadata.id, 'db-4');
        expect(event.metadata.deletedAt,
            DateTime.parse('2024-01-05T00:00:00.000'));
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
            newRecord: {
              'id': 'src-a',
              'data': json.encode({'name': 'First'}),
            },
          ),
          'pictures',
        );

        cloud.handlePostgresChange(
          _payload(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'src-b',
              'data': json.encode({'name': 'Second'}),
            },
          ),
          'records',
        );

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 2);
        expect(events[0], isA<CloudInsertedEvent>());
        expect((events[0] as CloudInsertedEvent).metadata.id, 'src-a');
        expect(events[1], isA<CloudUpdatedEvent>());
        expect((events[1] as CloudUpdatedEvent).metadata.id, 'src-b');
      });
    });
  });
}
