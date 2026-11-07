import 'package:test/test.dart';
import 'package:time_machine_cloud/time_machine_cloud.dart';
import 'package:time_machine_server/cloud_cache.dart';

void main() {
  test('HTTP-only requests use a temporary cloud', () async {
    final created = <_FakeCloud>[];
    final pollingFlags = <bool>[];
    final cache = CloudCache((provider, token, {startPolling = false}) async {
      pollingFlags.add(startPolling);
      final cloud = _FakeCloud('$provider/${created.length + 1}');
      created.add(cloud);
      return CloudInit(cloud, cloud.id);
    });

    final lease = await cache.acquire('dropbox', 'token');
    expect(lease.id, 'dropbox/1');
    expect(created, hasLength(1));
    expect(pollingFlags, [false]);
    expect(created.single.disposed, isFalse);

    lease.release();
    expect(created.single.disposed, isTrue);
  });

  test('the socket anchors the cache and requests reuse it', () async {
    final created = <_FakeCloud>[];
    final pollingFlags = <bool>[];
    final cache = CloudCache((provider, token, {startPolling = false}) async {
      pollingFlags.add(startPolling);
      final cloud = _FakeCloud('$provider/${created.length + 1}');
      created.add(cloud);
      return CloudInit(cloud, cloud.id);
    });

    final socket = await cache.acquire('dropbox', 'token', anchor: true);
    final first = await cache.acquire('dropbox', 'token');
    final second = await cache.acquire('dropbox', 'token');

    expect(created, hasLength(1));
    expect(pollingFlags, [true]);
    expect(identical(socket.cloud, first.cloud), isTrue);
    expect(identical(first.cloud, second.cloud), isTrue);

    first.release();
    expect(created.single.disposed, isFalse);

    socket.release();
    expect(created.single.disposed, isFalse, reason: 'a request still uses it');

    // A request that arrives after the socket is gone still reuses the entry.
    final third = await cache.acquire('dropbox', 'token');
    expect(created, hasLength(1));
    third.release();

    second.release();
    expect(created.single.disposed, isTrue);
  });

  test('multiple sockets share one entry until the last one closes', () async {
    final created = <_FakeCloud>[];
    final cache = CloudCache((provider, token, {startPolling = false}) async {
      final cloud = _FakeCloud('$provider/${created.length + 1}');
      created.add(cloud);
      return CloudInit(cloud, cloud.id);
    });

    final first = await cache.acquire('dropbox', 'token', anchor: true);
    final second = await cache.acquire('dropbox', 'token', anchor: true);

    expect(created, hasLength(1));
    first.release();
    expect(created.single.disposed, isFalse);
    second.release();
    expect(created.single.disposed, isTrue);
  });

  test('an idle session is not cached after all leases are released', () async {
    final created = <_FakeCloud>[];
    final cache = CloudCache((provider, token, {startPolling = false}) async {
      final cloud = _FakeCloud('$provider/${created.length + 1}');
      created.add(cloud);
      return CloudInit(cloud, cloud.id);
    });

    final socket = await cache.acquire('dropbox', 'token', anchor: true);
    socket.release();
    expect(created.single.disposed, isTrue);

    final later = await cache.acquire('dropbox', 'token');
    expect(created, hasLength(2));
    expect(created.last.disposed, isFalse);
    later.release();
    expect(created.last.disposed, isTrue);
  });
}

class _FakeCloud extends CloudBase {
  _FakeCloud(this.id);

  final String id;
  bool disposed = false;

  @override
  Future<String> initialize() async => id;

  @override
  Stream<CloudSyncEvent> get changes => const Stream.empty();

  @override
  bool get supportsEvents => false;

  @override
  Map<Type, String> get collectionNames => const {};

  @override
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) =>
      throw UnimplementedError();

  @override
  Future<List<CloudMetadata>> listRecords(
    String collection, {
    DateTime? since,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteRecord(String collection, String id) =>
      throw UnimplementedError();

  @override
  void dispose() {
    disposed = true;
  }
}
