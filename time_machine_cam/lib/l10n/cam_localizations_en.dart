// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CamLocalizationsEn extends CamLocalizations {
  CamLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cameraNotSupported => 'This functionality is not supported yet';

  @override
  String get couldNotImportPhoto =>
      'Could not import the photo due to an unexpected error';

  @override
  String get couldNotTakePhoto =>
      'Could not take the photo due to an unexpected error';

  @override
  String distanceInMeters(Object distance) {
    return '$distance m';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Km';

  @override
  String get importPage => 'Import picture';

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
  String get pictureAddedToGallery => 'Picture added to the gallery';

  @override
  String get viewPicture => 'View';
}
