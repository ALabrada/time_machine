import 'package:shared_preferences/shared_preferences.dart';

final class ConfigurationService {
  static const defaultCameraPictureOpacity = 0.5;
  static const defaultCameraRatio = '16x9';
  static const defaultGeocoder = "osm";
  static const defaultMaxYear = 2000;
  static const defaultMinYear = 1900;

  const ConfigurationService({
    required this.preferences,
  });

  final SharedPreferencesWithCache? Function() preferences;

  double? get cameraPictureOpacity => preferences()?.getDouble('settings.cameraPictureOpacity');
  set cameraPictureOpacity(double? value) {
    if (value == null) {
      preferences()?.remove('settings.cameraPictureOpacity');
    } else {
      preferences()?.setDouble('settings.cameraPictureOpacity', value);
    }
  }

  String? get cameraRatio => preferences()?.getString('settings.cameraRatio');
  set cameraRatio(String? value) {
    if (value == null) {
      preferences()?.remove('settings.cameraRatio');
    } else {
      preferences()?.setString('settings.cameraRatio', value);
    }
  }

  String? get geocoder => preferences()?.getString('settings.geocoder');
  set geocoder(String? value) {
    if (value == null) {
      preferences()?.remove('settings.geocoder');
    } else {
      preferences()?.setString('settings.geocoder', value);
    }
  }

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

  String? get tileServer => preferences()?.getString('settings.tileServer');
  set tileServer(String? value) {
    if (value == null) {
      preferences()?.remove('settings.tileServer');
    } else {
      preferences()?.setString('settings.tileServer', value);
    }
  }
}