// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class ConfigLocalizationsEs extends ConfigLocalizations {
  ConfigLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get helpPage => 'Preguntas Frequentes';

  @override
  String get questionHowToFindPicturesBody =>
      'Puede buscar fotos en su vecindad (pestaña **Cerca**) o en el map (pestaña **Mapa**). La aplicación descargará las fotos de bases de datos en línea, así que deberá estar conectada a internet. Puede elegir cúales bases de datos utilizar, entre otros parámetros, en la configuración (pestaña **Opciones**).';

  @override
  String get questionHowToFindPicturesTitle =>
      '¿Cómo encontrar fotos históricas?';

  @override
  String get questionHowToImportPicturesBody =>
      'Cuando seleccione la opción de import foto, deberá buscar la foto deseada en el teléfono. Cuando la seleccione, se mostrará la foto superpuesta con la foto histórica. Alinee las fotos lo más cercanamente posible y presione el botón **Guardar**. A continuación se abrirá la vista de **Comparación**.';

  @override
  String get questionHowToImportPicturesTitle =>
      '¿Cómo importar réplicas de fotos históricas?';

  @override
  String get questionHowToReplicatePictureBody =>
      'Luego de encontrar una foto histórica en su vecindad o en el mapa, puede tomar una foto en la aplicación, o importar una foto existente del teléfono. Primeramente, presione brevemente o unos segundos, y luego seleccione la opción deseada de la barra de opciones o del menú, según sea el caso.';

  @override
  String get questionHowToReplicatePictureTitle =>
      '¿Cómo crear una réplica de una foto histórica?';

  @override
  String get questionHowToSharePicturesBody =>
      'Puede compartir una foto histórica junto con su réplica desde la vista de **Comparación**, presionando el botón correspondiente. El menú permite publicar las fotos en el sitio [Re.Photos](https://www.re.photos), en nuestro [canal de Telegram](https://t.me/history_lens_app), entre otros métodos. Para publicar en [Re.Photos](https://www.re.photos) se abrirá el sitio web y deberá completar el formulario de creación, pero primeramente deberá acceder a su cuenta (o crear una nueva si no tiene). \n\nEs mejor compartir las versiones originales de las fotos históricas, obtenidas desde sus sitios web, para evitar marcas de agua. Puede abrir el sitio web de origen, seleccionando la foto histórica y presionando el botón **Navegador**.';

  @override
  String get questionHowToSharePicturesTitle => '¿Cómo compartir mis fotos?';

  @override
  String get questionHowToTakePictureBody =>
      'Cuando abra la cámara para tomar una foto, la foto histórica aparecerá montada sobre la vista de la cámara. Si se encuentra lejos del lugar de la foto histórica, en la esquina superior izquierda se mostrarán instrucciones para arribar al lugar. Entonces, alinee la foto histórica con la vista de la cámara lo más cercanamente posible. Cuando se guarde la foto, podrá abir la vista de **Comparación** o continuar tomando fotos.';

  @override
  String get questionHowToTakePictureTitle =>
      '¿Cómo tomar fotos en la aplicación?';

  @override
  String get questionWhatDataIsCollectedBody =>
      'Toda la aplicación recolectada por la aplicación se almacena localmente en el teléfono. Los datos se comparten solamente cuando usted explícitamente publica las fotos. Las fotos tomadas además contienen las coordenadas geográficas correspondientes.';

  @override
  String get questionWhatDataIsCollectedTitle =>
      '¿Qué datos recolecta la aplicación acerca de mí?';

  @override
  String get questionWhatIsAppPurposeBody =>
      'La aplicación permite descubir fotos antiguas y recrearlas, con el fin de compararlas con el presente. Además, puede compartir las fotos en [Re.Photos](https://www.re.photos) o en nuestro [canal de Telegram](https://t.me/history_lens_app).';

  @override
  String get questionWhatIsAppPurposeTitle =>
      '¿Cuál el es propósito de la aplicación Lentes de la Historia?';

  @override
  String get sectionDataBases => 'Base de Datos de Imágenes';

  @override
  String get sectionCamera => 'Cámara';

  @override
  String get sectionInformation => 'Información';

  @override
  String get sectionMap => 'Mapa';

  @override
  String get sectionSearchOptions => 'Opciones de Búsqueda';

  @override
  String get settingGeocoder => 'Base de Datos de Direcciones';

  @override
  String get settingHelp => 'Preguntas Frequentes';

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
