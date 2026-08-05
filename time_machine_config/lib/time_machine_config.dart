import 'package:flutter/material.dart';

export 'controllers/configuration_controller.dart';
export 'controllers/selection_controller.dart';
export 'domain/map_tile_server.dart';
export 'domain/selectable_item.dart';
export 'l10n/config_localizations.dart';
export 'pages/configuration_page.dart';
export 'pages/help_page.dart';
export 'services/configuration_service.dart';

ThemeMode themeModeOf(String value) {
  switch (value) {
    case 'dark':
      return ThemeMode.dark;
    case 'light':
      return ThemeMode.light;
    default:
      return ThemeMode.system;
  }
}
