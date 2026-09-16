import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_machine_config/controllers/cloud_controller.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

class _FakeCloud extends CloudBase with EventlessCloud {
  @override
  Map<Type, String> get collectionNames => const {};

  @override
  Future<String> initialize() async => 'fake/user';

  @override
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getRecord(
    String collection,
    String id,
  ) async =>
      null;

  @override
  Future<List<CloudMetadata>> listRecords(
    String collection, {
    DateTime? since,
  }) async =>
      const [];

  @override
  Future<void> deleteRecord(String collection, String id) async {}

  String? get userEmail => null;
}

class _InMemoryYandexTokenStore implements YandexDiskTokenStore {
  YandexDiskSession? session;

  @override
  Future<YandexDiskSession?> read() async => session;

  @override
  Future<void> write(YandexDiskSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

class _FakeYandexDiskCloud extends YandexDiskCloud {
  _FakeYandexDiskCloud()
      : super(
          clientId: 'test-client',
          tokenStore: _InMemoryYandexTokenStore(),
        );

  @override
  Future<String> initialize() async => 'yandex/fake-user';

  @override
  String? get userEmail => 'fake@example.com';

  @override
  Future<CloudMetadata> saveRecord(
    String collection,
    CloudMetadata? metadata,
    Map<String, dynamic> data,
  ) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getRecord(
    String collection,
    String id,
  ) async =>
      null;

  @override
  Future<List<CloudMetadata>> listRecords(
    String collection, {
    DateTime? since,
  }) async =>
      const [];

  @override
  Future<void> deleteRecord(String collection, String id) async {}
}

class _StallableFakeYandexDiskCloud extends _FakeYandexDiskCloud {
  Completer<void>? _gate = Completer<void>();

  /// Unblocks the in-flight sync by letting the stalled record fetches finish.
  Future<void> releaseSync() async {
    final gate = _gate;
    if (gate != null) {
      gate.complete();
      await gate.future;
    }
  }

  @override
  Future<List<CloudMetadata>> listRecords(
    String collection, {
    DateTime? since,
  }) async {
    final gate = _gate;
    if (gate != null) {
      await gate.future;
      _gate = null;
    }
    return const [];
  }
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigurationService configurationService;
  late NetworkService networkService;
  late CloudSyncService cloudSyncService;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    configurationService = ConfigurationService(preferences: () => prefs);
    networkService = NetworkService(
      clouds: {'alpha': _FakeCloud(), 'beta': _FakeCloud()},
      geocoders: {},
      providers: {},
    );
    cloudSyncService = CloudSyncService();
  });

  group('selectCloud', () {
    test('persists the selection when no cloud is configured', () async {
      final controller = CloudController(
        configurationService: configurationService,
        networkService: networkService,
        cloudSyncService: cloudSyncService,
      );

      expect(configurationService.cloud, isNull);

      controller.selectCloud('alpha');
      await _pump();

      expect(configurationService.cloud, 'alpha');
      expect(controller.cloudName, 'alpha');
    });

    test('re-selecting the same provider reloads without changing config',
        () async {
      configurationService.cloud = 'alpha';
      final controller = CloudController(
        configurationService: configurationService,
        networkService: networkService,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      controller.selectCloud('alpha');
      await _pump();

      expect(configurationService.cloud, 'alpha');
      expect(controller.cloudName, 'alpha');
    });

    test('switching provider persists the new selection', () async {
      configurationService.cloud = 'alpha';
      final controller = CloudController(
        configurationService: configurationService,
        networkService: networkService,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      controller.selectCloud('beta');
      await _pump();

      expect(configurationService.cloud, 'beta');
      expect(controller.cloudName, 'beta');
    });

    test('showSelection displays the provider list', () async {
      configurationService.cloud = 'alpha';
      final controller = CloudController(
        configurationService: configurationService,
        networkService: networkService,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      controller.showSelection();

      expect(controller.value, isA<NotSelectedState>());
      final state = controller.value as NotSelectedState;
      expect(state.clouds, containsAll(['alpha', 'beta']));
    });
  });

  group('status refresh', () {
    test('flips to active when the sync service becomes active after load',
        () async {
      final db = await databaseFactoryMemory.openDatabase('test_active.db');
      final databaseService = DatabaseService(db: db);
      final cloud = _FakeYandexDiskCloud();
      final network = NetworkService(
        clouds: {'yandex': cloud},
        geocoders: {},
        providers: {},
      );
      configurationService.cloud = 'yandex';

      final controller = CloudController(
        configurationService: configurationService,
        networkService: network,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      expect(controller.value, isA<YandexDiskState>());
      expect((controller.value as YandexDiskState).isActive, false);

      await cloudSyncService.init(
        databaseService: databaseService,
        provider: cloud,
      );
      await _pump();

      expect((controller.value as YandexDiskState).isActive, true);

      controller.dispose();
      await cloudSyncService.dispose();
    });

    test('keeps the provider selection open when the status changes',
        () async {
      final db = await databaseFactoryMemory.openDatabase('test_selection.db');
      final databaseService = DatabaseService(db: db);
      final network = NetworkService(
        clouds: {'yandex': _FakeYandexDiskCloud()},
        geocoders: {},
        providers: {},
      );
      configurationService.cloud = 'yandex';

      final controller = CloudController(
        configurationService: configurationService,
        networkService: network,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      controller.showSelection();
      expect(controller.value, isA<NotSelectedState>());

      await cloudSyncService.init(
        databaseService: databaseService,
        provider: null,
      );
      await _pump();

      expect(controller.value, isA<NotSelectedState>());

      controller.dispose();
      await cloudSyncService.dispose();
    });

    test('shows a loading screen while the initial sync is still running',
        () async {
      final db = await databaseFactoryMemory.openDatabase('test_sync_loading.db');
      final databaseService = DatabaseService(db: db);
      final cloud = _StallableFakeYandexDiskCloud();
      final network = NetworkService(
        clouds: {'yandex': cloud},
        geocoders: {},
        providers: {},
      );
      configurationService.cloud = 'yandex';

      unawaited(cloudSyncService.init(
        databaseService: databaseService,
        provider: cloud,
      ));
      for (var i = 0; i < 50 && !cloudSyncService.syncBusy; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(cloudSyncService.syncBusy, isTrue);

      final controller = CloudController(
        configurationService: configurationService,
        networkService: network,
        cloudSyncService: cloudSyncService,
      );
      await _pump();

      expect(controller.value, isA<LoadingState>());
      expect(
        (controller.value as LoadingState).phase,
        CloudLoadingPhase.synchronizing,
      );

      await cloud.releaseSync();
      await _pump();

      expect(controller.value, isA<YandexDiskState>());
      expect((controller.value as YandexDiskState).isActive, true);

      controller.dispose();
      await cloudSyncService.dispose();
    });
  });
}