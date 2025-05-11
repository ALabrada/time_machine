// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class ConfigLocalizationsRu extends ConfigLocalizations {
  ConfigLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get sectionDataBases => 'Базы Данных Изображений';

  @override
  String get sectionCamera => 'Камера';

  @override
  String get sectionMap => 'Карта';

  @override
  String get sectionSearchOptions => 'Параметры Поиска';

  @override
  String get settingMapProvider => 'Картографический Сервис';

  @override
  String get settingPictureRatio => 'Соотношение Сторон Изображения';

  @override
  String get settingReferenceOpacity => 'Прозрачность Эталона';

  @override
  String get settingSearchBeginning => 'Начало (год)';

  @override
  String get settingSearchEnd => 'Конец (года)';
}
