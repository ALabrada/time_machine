import 'package:flutter/cupertino.dart';
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
        )
  {
    updateYears();
    updateTileServers();
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
    for (final provider in providers) {
      provider.addListener(() {
        updateProvider(provider.item, provider.value);
        notifyListeners();
      });
    }
  }

  final NetworkService? networkService;
  final ConfigurationService configurationService;

  final SelectionController<int> maxYear;
  final SelectionController<int> minYear;
  final List<SelectableItem<String>> providers;
  final SelectionController<String> tileServer;

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

  void updateTileServers() {
    tileServer.elements.value = MapTileServer.values
        .map((e) => e.id)
        .toList();
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

  static List<SelectableItem<String>> _createProviders({
    required ConfigurationService configurationService,
    NetworkService? networkService,
  }) {
    return [
      if (networkService?.providers.containsKey('pastvu') ?? false)
        SelectableItem(
          title: "PastVu",
          item: 'pastvu',
          value: configurationService.providers?.contains('pastvu') ?? true,
        ),
      if (networkService?.providers.containsKey('russiainphoto') ?? false)
        SelectableItem(
          title: "Russia in Photo",
          item: 'russiainphoto',
          value: configurationService.providers?.contains('russiainphoto') ?? true,
        ),
    ];
  }
}