import 'package:flutter/material.dart';
import 'package:select_dialog/select_dialog.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:time_machine_config/controllers/configuration_controller.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_net/services/network_service.dart';
import 'package:provider/provider.dart';

import '../controllers/selection_controller.dart';

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
              _buildCameraSection(),
              _buildMapSection(),
              _buildProvidersSection(),
              _buildSearchOptions(),
            ],
          );
        },
      ),
    );
  }

  AbstractSettingsSection _buildCameraSection() {
    return SettingsSection(
      title: Text("Camera"),
      tiles: [
        SettingsTile.navigation(
          title: Text("Picture Ratio"),
          value: Text(controller.cameraRatio.value),
          onPressed: (_) => _showSelectionDialog(
            label: "Picture Ratio",
            controller: controller.cameraRatio,
          ),
        ),
        SettingsTile(
          title: Text("Reference Opacity"),
          value: Text('${(100 * controller.cameraPictureOpacity).toStringAsFixed(0)}%'),
          trailing: Slider(
            value: controller.cameraPictureOpacity,
            min: 0,
            max: 1,
            onChanged: (v) => controller.cameraPictureOpacity = v,
          ),
        ),
      ],
    );
  }

  AbstractSettingsSection _buildMapSection() {
    return SettingsSection(
      title: Text("Map"),
      tiles: [
        SettingsTile.navigation(
          title: Text("Provider"),
          value: Text(controller.tileServer.value),
          onPressed: (_) => _showSelectionDialog(
            label: "Map Provider",
            controller: controller.tileServer,
          ),
        ),
      ],
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
        SettingsTile.navigation(
          title: Text("Beginning (year)"),
          value: Text(controller.minYear.value.toString()),
          onPressed: (_) => _showSelectionDialog(
            label: "Beginning (year)",
            controller: controller.minYear,
          ),
        ),
        SettingsTile.navigation(
          title: Text("End (year)"),
          value: Text(controller.maxYear.value.toString()),
          onPressed: (_) => _showSelectionDialog(
            label: "End (year)",
            controller: controller.maxYear,
          ),
        ),
      ],
    );
  }

  Future<void> _showSelectionDialog<T>({
    required String label,
    required SelectionController<T> controller,
  }) async {
    await SelectDialog.showModal<T>(context,
      label: label,
      selectedValue: controller.value,
      items: controller.elements.value,
      onChange: (v) => controller.value = v,
    );
  }
}
