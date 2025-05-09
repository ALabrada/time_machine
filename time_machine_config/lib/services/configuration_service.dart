import 'package:shared_preferences/shared_preferences.dart';

final class ConfigurationService {
  static const defaultMaxYear = 2000;
  static const defaultMinYear = 1900;

  const ConfigurationService({
    required this.preferences,
  });

  final SharedPreferencesWithCache? Function() preferences;

  List<String>? get providers => preferences()?.getStringList('settings.providers');
  set providers(List<String>? value) {
    if (value == null) {
      preferences()?.remove('settings.providers');
    } else {
      preferences()?.setStringList('settings.providers', value);
    }
  }

  int? get minYear => preferences()?.getInt('settings.minYear');
  set minYear(int? value) {
    if (value == null) {
      preferences()?.remove('settings.minYear');
    } else {
      preferences()?.setInt('settings.minYear', value);
    }
  }

  int? get maxYear => preferences()?.getInt('settings.maxYear');
  set maxYear(int? value) {
    if (value == null) {
      preferences()?.remove('settings.maxYear');
    } else {
      preferences()?.setInt('settings.maxYear', value);
    }
  }
}