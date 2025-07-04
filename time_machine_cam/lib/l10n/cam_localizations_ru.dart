// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class CamLocalizationsRu extends CamLocalizations {
  CamLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get couldNotImportPhoto =>
      'Не удалось импортировать фотографию из-за непредвиденной ошибки';

  @override
  String get couldNotTakePhoto =>
      'Не удалось сделать фотографию из-за непредвиденной ошибки';

  @override
  String distanceInMeters(Object distance) {
    return '$distance м';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Км';

  @override
  String get importPage => 'Импортировать фотографию';

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
  String get pictureAddedToGallery => 'Фотография добавлена в галерею';

  @override
  String get viewPicture => 'Посмотреть';
}
