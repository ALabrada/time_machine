// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class ConfigLocalizationsEs extends ConfigLocalizations {
  ConfigLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get sectionDataBases => 'Base de Datos de Imágenes';

  @override
  String get sectionCamera => 'Cámara';

  @override
  String get sectionMap => 'Mapa';

  @override
  String get sectionSearchOptions => 'Opciones de Búsqueda';

  @override
  String get settingMapProvider => 'Servicio de Mapas';

  @override
  String get settingPictureRatio => 'Relación de Aspecto';

  @override
  String get settingReferenceOpacity => 'Opacidad de la Referencia';

  @override
  String get settingSearchBeginning => 'Inicio (año)';

  @override
  String get settingSearchEnd => 'Fin (año)';
}
