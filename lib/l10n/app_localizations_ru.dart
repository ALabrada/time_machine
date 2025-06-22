// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Линзы Истории';

  @override
  String get homeTabsGallery => 'Галерея';

  @override
  String get homeTabsCamera => 'Поблизости';

  @override
  String get homeTabsMap => 'Карта';

  @override
  String get homeTabsConfig => 'Настройки';
}
