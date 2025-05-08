import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:time_machine_config/controllers/configuration_controller.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_net/services/network_service.dart';
import 'package:provider/provider.dart';

class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({
    super.key,
  });

  @override
  _ConfigurationPageState createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  late ConfigurationController controller;

  @override
  void initState() {
    controller = ConfigurationController(
      configurationService: context.read(),
      networkService: context.read(),
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return SettingsList(
            sections: [
              _buildProvidersSection(),
              _buildSearchOptions(),
            ],
          );
        },
      ),
    );
  }

  AbstractSettingsSection _buildProvidersSection() {
    return SettingsSection(
      title: Text("Data Providers"),
      tiles: [
        for (final provider in controller.providers)
          SettingsTile.switchTile(
            initialValue: provider.value,
            onToggle: (value) => provider.value = value,
            title: Text(provider.title ?? ''),
          ),
      ],
    );
  }

  AbstractSettingsSection _buildSearchOptions() {
    return SettingsSection(
      title: Text("Search Options"),
      tiles: [
        SettingsTile(
          title: Text('Beginning (year)'),
          value: Text(controller.minYear.value.toString()),
        ),
        SettingsTile(
          title: Text('End (year)'),
          value: Text(controller.maxYear.value.toString()),
        ),
      ],
    );
  }
}
