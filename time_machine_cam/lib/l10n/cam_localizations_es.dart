// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'cam_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class CamLocalizationsEs extends CamLocalizations {
  CamLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get couldNotImportPhoto =>
      'No se pudo obtener la foto debido a un error inesperado';

  @override
  String get couldNotTakePhoto =>
      'No se pudo importar la foto debido a un error inesperado';

  @override
  String distanceInMeters(Object distance) {
    return '$distance m';
  }

  @override
  String get distanceGreaterThan1Km => '+1 Km';

  @override
  String get importPage => 'Importar foto';

  @override
  String get menuTitle => 'Opciones';

  @override
  String get menuActionCamera => 'Tomar foto';

  @override
  String get menuActionCancel => 'Cancelar';

  @override
  String get menuActionOpenSource => 'Abrir fuente';

  @override
  String get menuActionShare => 'Compartir foto';

  @override
  String get menuActionView => 'Ver foto';

  @override
  String get pictureAddedToGallery => 'Se añadió la foto a la galería';

  @override
  String get viewPicture => 'Ver';
}
