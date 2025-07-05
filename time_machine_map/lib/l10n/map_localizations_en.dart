// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'map_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class MapLocalizationsEn extends MapLocalizations {
  MapLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get locationNotFoundAction => 'Settings';

  @override
  String get locationNotFoundError =>
      'Could not determine your location. Please, check your location settings.';

  @override
  String get menuTitle => 'Options';

  @override
  String get menuActionCamera => 'Take replica of the picture';

  @override
  String get menuActionCancel => 'Cancel';

  @override
  String get menuActionImport => 'Import replica of the picture';

  @override
  String get menuActionOpenSource => 'Open source';

  @override
  String get menuActionShare => 'Share picture';

  @override
  String get menuActionView => 'Show picture';

  @override
  String get searchBarHint => 'Search...';
}
