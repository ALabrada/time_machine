// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ConfigLocalizationsEn extends ConfigLocalizations {
  ConfigLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get sectionDataBases => 'Picture DataBases';

  @override
  String get sectionCamera => 'Camera';

  @override
  String get sectionMap => 'Map';

  @override
  String get sectionSearchOptions => 'Search Options';

  @override
  String get settingMapProvider => 'Map Provider';

  @override
  String get settingPictureRatio => 'Picture Ratio';

  @override
  String get settingReferenceOpacity => 'Reference Opacity';

  @override
  String get settingSearchBeginning => 'Beginning (year)';

  @override
  String get settingSearchEnd => 'End (year)';
}
