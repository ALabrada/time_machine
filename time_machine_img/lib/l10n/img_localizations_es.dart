// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'img_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class ImgLocalizationsEs extends ImgLocalizations {
  ImgLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get creationMenuTitle => 'Crear réplica';

  @override
  String get creationMenuActionCamera => 'Tomar foto';

  @override
  String get creationMenuActionCancel => 'Cancelar';

  @override
  String get creationMenuActionImport => 'Importar foto de la galería';

  @override
  String get deleteCancel => 'Cancelar';

  @override
  String get deleteConfirm => 'Borrar';

  @override
  String get deleteManySubtitle =>
      '¿Está seguro de que desea borrar las réplicas?';

  @override
  String deleteManyTitle(Object count) {
    return 'Borrando $count';
  }

  @override
  String get deleteOneSubtitle =>
      '¿Está seguro de que desea borrar la réplica?';

  @override
  String get deleteOneTitle => 'Borrando';

  @override
  String get errorLoadingPage => 'No se pudo conectarse al servidor';

  @override
  String get comparisonPage => 'Comparación';

  @override
  String get comparisonBottom => 'Arriba';

  @override
  String get comparisonLeft => 'Izquierda';

  @override
  String get comparisonMetric => 'Similaridad';

  @override
  String get comparisonRight => 'Derecha';

  @override
  String get comparisonTop => 'Encima';

  @override
  String galleryEmptyListBody(
      Object importIcon, Object mapLink, Object nearbyLink) {
    return 'Puede comenzar buscando fotos históricas en su [cercanía]($nearbyLink) o en el [mapa]($mapLink). Cuando replique una foto histórica, su foto aparecerá aquí. También puede presionar $importIcon para importar sus fotos desde un archivo, si las exportó previamente usando la Aplicación.';
  }

  @override
  String get galleryEmptyListTitle => 'La galería está vacía';

  @override
  String get galleryNoSearchResults => 'No se encontraron resultados';

  @override
  String get galleryRecentPictures => 'Vistas recientemente';

  @override
  String get importError => 'No se pudo importar el archivo';

  @override
  String get importSuccessful => 'Archivo importado correctamente';

  @override
  String get searchBarHint => 'Buscar...';

  @override
  String get shareMenu => '¿Cómo desea compartir?';

  @override
  String get shareMenuCancel => 'Cancelar';

  @override
  String get shareMenuExport => 'Exportar datos';

  @override
  String get shareMenuImages => 'Compartir imágenes';

  @override
  String shareMenuPublishTo(Object site) {
    return 'Publicar en $site';
  }

  @override
  String shareMenuUploadTo(Object site) {
    return 'Subir a $site';
  }

  @override
  String get uploadMenu => '¿Qué desea enviar?';

  @override
  String get uploadMenuCancel => 'Cancelar';

  @override
  String get uploadMenuFile => 'Otro archivo';

  @override
  String get uploadMenuFileAligned => 'Otro archivo (Alineado)';

  @override
  String get uploadMenuOriginal => 'La foto antigua';

  @override
  String get uploadMenuOriginalAligned => 'La foto antigua (Alineado)';

  @override
  String get uploadMenuPicture => 'Su foto';

  @override
  String get uploadMenuPictureAligned => 'Su foto (Alineado)';

  @override
  String uploadPage(Object site) {
    return 'Subir a $site';
  }
}
