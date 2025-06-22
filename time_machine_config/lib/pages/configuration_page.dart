import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:select_dialog/select_dialog.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:time_machine_config/controllers/configuration_controller.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_net/services/network_service.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../l10n/config_localizations.dart';
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
            applicationType: ApplicationType.material,
            sections: [
              _buildCameraSection(),
              _buildMapSection(),
              _buildProvidersSection(),
              _buildSearchOptions(),
              _buildFooter(),
            ],
          );
        },
      ),
    );
  }

  AbstractSettingsSection _buildFooter() {
    final packageInfo = context.watch<PackageInfo?>();
    return CustomSettingsSection(
      child: Container(
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surface,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: packageInfo == null ? null : Text('${packageInfo.appName} v${packageInfo.version}'),
      ),
    );
  }

  AbstractSettingsSection _buildCameraSection() {
    return SettingsSection(
      title: Text(ConfigLocalizations.of(context).sectionCamera),
      tiles: [
        SettingsTile.navigation(
          title: Text(ConfigLocalizations.of(context).settingPictureRatio),
          value: Text(controller.cameraRatio.value),
          onPressed: (_) => _showSelectionDialog(
            label: ConfigLocalizations.of(context).settingPictureRatio,
            controller: controller.cameraRatio,
          ),
        ),
        SettingsTile(
          title: Text(ConfigLocalizations.of(context).settingReferenceOpacity),
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
      title: Text(ConfigLocalizations.of(context).sectionMap),
      tiles: [
        SettingsTile.navigation(
          title: Text(ConfigLocalizations.of(context).settingMapProvider),
          value: Text(controller.tileServer.value),
          onPressed: (_) => _showSelectionDialog(
            label: ConfigLocalizations.of(context).settingMapProvider,
            controller: controller.tileServer,
          ),
        ),
        SettingsTile.navigation(
          title: Text(ConfigLocalizations.of(context).settingGeocoder),
          value: Text(controller.geocoder.value),
          onPressed: (_) => _showSelectionDialog(
            label: ConfigLocalizations.of(context).settingGeocoder,
            controller: controller.geocoder,
          ),
        ),
      ],
    );
  }

  AbstractSettingsSection _buildProvidersSection() {
    final names = {
      'pastvu': 'PastVu',
      'russiainphoto': 'История России в фотографиях',
    };
    final links = {
      'pastvu': 'https://pastvu.com/',
      'russiainphoto': 'https://russiainphoto.ru/',
    };
    return SettingsSection(
      title: Text(ConfigLocalizations.of(context).sectionDataBases),
      tiles: [
        for (final provider in controller.providers)
          SettingsTile.switchTile(
            initialValue: provider.value,
            onToggle: (value) => provider.value = value,
            title: Text(names[provider.item] ?? '?'),
            description: InkWell(
              onTap: () => unawaited(launchUrlString(links[provider.item] ?? '?')),
              child: Text(links[provider.item] ?? '?',
                style: TextStyle(color: Theme.of(context).colorScheme.secondary),
              ),
            ),
          ),
      ],
    );
  }

  AbstractSettingsSection _buildSearchOptions() {
    return SettingsSection(
      title: Text(ConfigLocalizations.of(context).sectionSearchOptions),
      tiles: [
        SettingsTile.navigation(
          title: Text(ConfigLocalizations.of(context).settingSearchBeginning),
          value: Text(controller.minYear.value.toString()),
          onPressed: (_) => _showSelectionDialog(
            label: ConfigLocalizations.of(context).settingSearchBeginning,
            controller: controller.minYear,
          ),
        ),
        SettingsTile.navigation(
          title: Text(ConfigLocalizations.of(context).settingSearchEnd),
          value: Text(controller.maxYear.value.toString()),
          onPressed: (_) => _showSelectionDialog(
            label: ConfigLocalizations.of(context).settingSearchEnd,
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
