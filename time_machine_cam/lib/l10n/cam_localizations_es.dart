// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class CamLocalizationsEs extends CamLocalizations {
  CamLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String distanceInMeters(Object distance) {
    return '$distance m';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Km';

  @override
  String get pictureAddedToGallery => 'Se añadió la foto a la galería';

  @override
  String get viewPicture => 'Ver';
}
