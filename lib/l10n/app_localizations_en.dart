// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'History Lens';

  @override
  String get homeTabsGallery => 'Gallery';

  @override
  String get homeTabsCamera => 'Nearby';

  @override
  String get homeTabsMap => 'Map';

  @override
  String get homeTabsConfig => 'Settings';
}
