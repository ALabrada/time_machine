import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class ConfigurationService extends ChangeNotifier {
  static const defaultCameraPictureOpacity = 0.5;
  static const defaultCameraRatio = '16x9';
  static const defaultGeocoder = "OSM";
  static const defaultMaxYear = 2000;
  static const defaultMinYear = 1900;
  static const defaultVolumeButton = true;

  ConfigurationService({
    required this.preferences,
  });

  final SharedPreferencesWithCache? Function() preferences;

  String? get themeMode => preferences()?.getString('settings.themeMode');
  set themeMode(String? value) {
    if (value == null) {
      preferences()?.remove('settings.themeMode');
    } else {
      preferences()?.setString('settings.themeMode', value);
    }
    notifyListeners();
  }

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

  bool? get volumeButton => preferences()?.getBool('settings.volumeButton');
  set volumeButton(bool? value) {
    if (value == null) {
      preferences()?.remove('settings.volumeButton');
    } else {
      preferences()?.setBool('settings.volumeButton', value);
    }
  }
}