// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'map_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class MapLocalizationsRu extends MapLocalizations {
  MapLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get locationNotFoundAction => 'Настройки';

  @override
  String get locationNotFoundError =>
      'Не удалось определить ваше местоположение. Пожалуйста, проверьте настройки.';

  @override
  String get menuTitle => 'Опций';

  @override
  String get menuActionCamera => 'Сфотографировать реплику фотографии';

  @override
  String get menuActionCancel => 'Отменить';

  @override
  String get menuActionImport => 'Импортировать реплику фотографии';

  @override
  String get menuActionOpenSource => 'Открыть источник';

  @override
  String get menuActionShare => 'Поделиться фотографией';

  @override
  String get menuActionView => 'Посмотреть фотографию';

  @override
  String get searchBarHint => 'Поискать...';
}
