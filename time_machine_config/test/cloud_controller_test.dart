import 'package:flutter_test/flutter_test.dart';
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
}