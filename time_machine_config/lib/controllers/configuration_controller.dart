import 'package:flutter/foundation.dart';
import 'package:time_machine_config/controllers/selection_controller.dart';
import 'package:time_machine_config/domain/map_tile_server.dart';
import 'package:time_machine_config/domain/selectable_item.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_net/time_machine_net.dart';

final class ConfigurationController extends ChangeNotifier {
  ConfigurationController({
    required this.configurationService,
    this.networkService,
  }) :
        cameraRatio = SelectionController<String>(
          value: configurationService.cameraRatio ?? ConfigurationService.defaultCameraRatio,
          elements: ['16x9', '4x3', '1x1'],
        ),
        geocoder = _createGeocoders(
          configurationService: configurationService,
          networkService: networkService,
        ),
        maxYear = SelectionController<int>(
          value: configurationService.maxYear ?? ConfigurationService.defaultMaxYear,
        ),
        minYear = SelectionController<int>(
          value: configurationService.minYear ?? ConfigurationService.defaultMinYear,
        ),
        providers = _createProviders(
          configurationService: configurationService,
          networkService: networkService,
        ),
        tileServer = SelectionController(
          value: configurationService.tileServer ?? MapTileServer.values[0].id,
          elements: MapTileServer.values
              .map((e) => e.id)
              .toList(),
        ),
        themeMode = SelectionController<String>(
          value: _themeModeValue(configurationService.themeMode),
          elements: const ['system', 'light', 'dark'],
        )
  {
    updateYears();
    cameraRatio.addListener(() {
      configurationService.cameraRatio = cameraRatio.value;
      notifyListeners();
    });
    maxYear.addListener(() {
      configurationService.maxYear = maxYear.value;
      updateYears();
      notifyListeners();
    });
    minYear.addListener(() {
      configurationService.minYear = minYear.value;
      updateYears();
      notifyListeners();
    });
    tileServer.addListener(() {
      configurationService.tileServer = tileServer.value;
      notifyListeners();
    });
    geocoder.addListener(() {
      configurationService.geocoder = geocoder.value;
      notifyListeners();
    });
    themeMode.addListener(() {
      configurationService.themeMode = themeMode.value;
      notifyListeners();
    });
    for (final provider in providers) {
      provider.addListener(() {
        updateProvider(provider.item, provider.value);
        notifyListeners();
      });
    }
  }

  final NetworkService? networkService;
  final ConfigurationService configurationService;

  final SelectionController<String> cameraRatio;
  final SelectionController<String> geocoder;
  final SelectionController<int> maxYear;
  final SelectionController<int> minYear;
  final List<SelectableItem<String>> providers;
  final SelectionController<String> tileServer;
  final SelectionController<String> themeMode;

  double get cameraPictureOpacity => configurationService.cameraPictureOpacity
      ?? ConfigurationService.defaultCameraPictureOpacity;
  set cameraPictureOpacity(double value) {
    configurationService.cameraPictureOpacity = value;
    notifyListeners();
  }

  void updateProvider(String key, bool selected) {
    final providers = configurationService.providers
        ?? networkService?.providers.keys.toList()
        ?? [];
    if (!selected) {
      providers.remove(key);
    } else if (!providers.contains(key)) {
      providers.add(key);
    }
    configurationService.providers = providers;
  }

  void updateYears() {
    maxYear.elements.value = List.generate(
        ConfigurationService.defaultMaxYear - minYear.value + 1,
          (idx) => minYear.value + idx,
    );
    minYear.elements.value = List.generate(
      maxYear.value - ConfigurationService.defaultMinYear + 1,
          (idx) => ConfigurationService.defaultMinYear + idx,
    );
  }

  static SelectionController<String> _createGeocoders({
    required ConfigurationService configurationService,
    NetworkService? networkService,
  }) {
    final services = networkService?.geocoders.keys.toList();
    services?.sort();
    return SelectionController<String>(
      value: configurationService.geocoder ?? ConfigurationService.defaultGeocoder,
      elements: services ?? [],
    );
  }

  static String _themeModeValue(String? value) {
    switch (value) {
      case 'dark':
        return 'dark';
      case 'light':
        return 'light';
      default:
        return 'system';
    }
  }

  static List<SelectableItem<String>> _createProviders({
    required ConfigurationService configurationService,
    NetworkService? networkService,
  }) {
    return [
      if (networkService?.providers.containsKey('re.photos') ?? false)
        SelectableItem(
          item: 're.photos',
          value: configurationService.providers?.contains('re.photos') ?? true,
        ),
      if (networkService?.providers.containsKey('pastvu') ?? false)
        SelectableItem(
          item: 'pastvu',
          value: configurationService.providers?.contains('pastvu') ?? true,
        ),
      if (networkService?.providers.containsKey('historypin') ?? false)
        SelectableItem(
          item: 'historypin',
          value: configurationService.providers?.contains('historypin') ?? true,
        ),
      if (networkService?.providers.containsKey('sepiatown') ?? false)
        SelectableItem(
          item: 'sepiatown',
          value: configurationService.providers?.contains('sepiatown') ?? true,
        ),
      if (networkService?.providers.containsKey('russiainphoto') ?? false)
        SelectableItem(
          item: 'russiainphoto',
          value: configurationService.providers?.contains('russiainphoto') ?? true,
        ),
    ];
  }
}