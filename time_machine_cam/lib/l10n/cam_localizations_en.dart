// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CamLocalizationsEn extends CamLocalizations {
  CamLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String distanceInMeters(Object distance) {
    return '$distance m';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Km';

  @override
  String get pictureAddedToGallery => 'Picture added to the gallery';

  @override
  String get viewPicture => 'View';
}
