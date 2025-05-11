// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class CamLocalizationsRu extends CamLocalizations {
  CamLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String distanceInMeters(Object distance) {
    return '$distance м';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Км';

  @override
  String get pictureAddedToGallery => 'Фотография добавлена в галерею';

  @override
  String get viewPicture => 'Посмотреть';
}
