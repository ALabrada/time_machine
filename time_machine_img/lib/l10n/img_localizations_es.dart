// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'img_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class ImgLocalizationsEs extends ImgLocalizations {
  ImgLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get errorLoadingPage => 'No se pudo conectarse al servidor';

  @override
  String get comparisonPage => 'Comparación';

  @override
  String get comparisonBottom => 'Arriba';

  @override
  String get comparisonLeft => 'Izquierda';

  @override
  String get comparisonRight => 'Derecha';

  @override
  String get comparisonTop => 'Encima';

  @override
  String get galleryEmptyList => 'La galería está vacía';

  @override
  String get galleryNoSearchResults => 'No se encontraron resultados';

  @override
  String get searchBarHint => 'Buscar...';

  @override
  String get shareMenu => '¿Cómo desea compartir?';

  @override
  String get shareMenuCancel => 'Cancelar';

  @override
  String get shareMenuImages => 'Compartir imágenes';

  @override
  String shareMenuUploadTo(Object site) {
    return 'Subir a $site';
  }

  @override
  String get uploadMenu => '¿Qué desea enviar?';

  @override
  String get uploadMenuFile => 'Otro archivo';

  @override
  String get uploadMenuOriginal => 'La foto antigua';

  @override
  String get uploadMenuPicture => 'Su foto';

  @override
  String uploadPage(Object site) {
    return 'Subir a $site';
  }
}
