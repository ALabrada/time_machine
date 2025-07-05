// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'map_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class MapLocalizationsEs extends MapLocalizations {
  MapLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get locationNotFoundAction => 'Opciones';

  @override
  String get locationNotFoundError =>
      'No se pudo determinar su ubicación. Por favor, verifique las opciones.';

  @override
  String get menuTitle => 'Opciones';

  @override
  String get menuActionCamera => 'Tomar réplica de la foto';

  @override
  String get menuActionCancel => 'Cancelar';

  @override
  String get menuActionImport => 'Importar réplica de la foto';

  @override
  String get menuActionOpenSource => 'Abrir fuente';

  @override
  String get menuActionShare => 'Compartir foto';

  @override
  String get menuActionView => 'Ver foto';

  @override
  String get searchBarHint => 'Buscar...';
}
