import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/picture_controller.dart';
import 'package:time_machine_net/time_machine_net.dart';

import '../helpers/cloud_test_utils.dart';

class _NoopCacheManager extends BaseCacheManager {
  @override
  Future<File> getSingleFile(String url, {String? key, Map<String, String>? headers}) {
    throw UnimplementedError();
  }

  @override
  Stream<FileInfo> getFile(String url, {String? key, Map<String, String>? headers}) {
    throw UnimplementedError();
  }

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    throw UnimplementedError();
  }

  @override
  Future<FileInfo> downloadFile(String url,
      {String? key, Map<String, String>? authHeaders, bool force = false}) {
    throw UnimplementedError();
  }

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) {
    throw UnimplementedError();
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) {
    throw UnimplementedError();
  }

  @override
  Future<File> putFile(String url, Uint8List fileBytes,
      {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) {
    throw UnimplementedError();
  }

  @override
  Future<File> putFileStream(String url, Stream<List<int>> source,
      {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeFile(String key) => Future.value();

  @override
  Future<void> emptyCache() => Future.value();

  @override
  Future<void> dispose() => Future.value();
}

void main() {
  group('PictureController', () {
    late Database db;
    late DatabaseService dbService;
    late FakeCloudSyncProvider provider;
    late CloudSyncService sync;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'picture_controller_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      dbService = DatabaseService(db: db);
      provider = createTestProvider();
      sync = CloudSyncService();

      addTearDown(() async => await db.close());
      addTearDown(() async => await sync.dispose());
      addTearDown(provider.dispose);
    });

    /// Seeds a visited picture, lets the initial cloud sync push it, then
    /// starts watching it (returning the observed emissions).
    Future<Picture> seedPicture() async {
      final visitedAt = DateTime.now();
      final picture =
          await insertPicture(dbService, id: 'pic', provider: 'pastvu',
              description: 'old', visitedAt: visitedAt);
      await sync.init(databaseService: dbService, provider: provider);
      return picture;
    }

    (PictureController, List<Picture?>) watchPicture(int? localId) {
      final controller = PictureController(
        cacheService: CacheService(cacheManager: _NoopCacheManager()),
        databaseService: dbService,
        cloudSyncService: sync,
      );
      addTearDown(controller.dispose);
      final emissions = <Picture?>[];
      controller.pictureChanges.listen(emissions.add);
      controller.watchPicture(localId);
      return (controller, emissions);
    }

    test('emits the initial picture on watch', () async {
      final picture = await seedPicture();
      final (_, emissions) = watchPicture(picture.localId);

      await waitUntil(() => emissions.isNotEmpty);
      expect(emissions.single!.localId, picture.localId);
      expect(emissions.single!.description, 'old');
    });

    test('re-emits when syncWithCloud pulls a cloud description change',
        () async {
      final picture = await seedPicture();
      final (_, emissions) = watchPicture(picture.localId);
      await waitUntil(() => emissions.isNotEmpty);

      const key = 'pastvu/pic';
      final newUpdateAt = DateTime.now().add(const Duration(hours: 1));
      provider.addRecord('pictures', key,
          cloudPictureJson(id: 'pic', provider: 'pastvu', description: 'new',
              updateAt: newUpdateAt));

      await sync.syncWithCloud();

      await waitUntil(
        () => emissions.isNotEmpty && emissions.last!.description == 'new',
      );
    });

    test('re-emits when a CloudUpdatedEvent changes the description', () async {
      final picture = await seedPicture();
      final (_, emissions) = watchPicture(picture.localId);
      await waitUntil(() => emissions.isNotEmpty);

      const key = 'pastvu/pic';
      final newUpdateAt = DateTime.now().add(const Duration(hours: 2));
      provider.addRecord('pictures', key,
          cloudPictureJson(id: 'pic', provider: 'pastvu',
              description: 'from event', updateAt: newUpdateAt));
      provider.emitChange(CloudUpdatedEvent(
        metadata: cloudMetadata(id: key, updatedAt: newUpdateAt),
        collection: 'pictures',
      ));

      await waitUntil(
        () => emissions.isNotEmpty && emissions.last!.description == 'from event',
      );
    });

    test('updateDescription publishes the renamed picture', () async {
      final picture = await seedPicture();
      final (controller, emissions) = watchPicture(picture.localId);
      await waitUntil(() => emissions.isNotEmpty);

      await controller.updateDescription('renamed');

      await waitUntil(
        () => emissions.isNotEmpty && emissions.last!.description == 'renamed',
      );
      expect(
        (await dbService.createRepository<Picture>()
            .getById(picture.localId!))
            ?.description,
        'renamed',
      );
    });

    test('fires entityDeleted when syncWithCloud deletes the picture',
        () async {
      final picture = await seedPicture();
      final (controller, emissions) = watchPicture(picture.localId);
      await waitUntil(() => emissions.isNotEmpty);

      final deleted = <void>[];
      controller.entityDeleted.listen((_) => deleted.add(null));

      const key = 'pastvu/pic';
      final deletedAt = DateTime.now().add(const Duration(hours: 1));
      provider.addRecord('pictures', key, cloudPictureJson(
        id: 'pic',
        provider: 'pastvu',
        deletedAt: deletedAt,
      ));

      await sync.syncWithCloud();

      await waitUntil(() => deleted.isNotEmpty);
      expect(deleted.length, 1);
      expect(
        await dbService.createRepository<Picture>().getById(picture.localId!),
        isNull,
      );
    });
  });
}