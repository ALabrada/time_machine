// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'img_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class ImgLocalizationsRu extends ImgLocalizations {
  ImgLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get creationMenuTitle => 'Создать реплику';

  @override
  String get creationMenuActionCamera => 'Сфотографировать';

  @override
  String get creationMenuActionCancel => 'Отменить';

  @override
  String get creationMenuActionImport =>
      'Импортировать фотографию из библиотеки';

  @override
  String get deleteCancel => 'Отменить';

  @override
  String get deleteConfirm => 'Удалить';

  @override
  String get deleteManySubtitle => 'Вы уверены, что хотите удалить реплики?';

  @override
  String deleteManyTitle(Object count) {
    return 'Удалить $count';
  }

  @override
  String get deleteOneSubtitle => 'Вы уверены, что хотите удалить реплику?';

  @override
  String get deleteOneTitle => 'Удалить';

  @override
  String get errorLoadingPage => 'Не удалось подключиться к серверу';

  @override
  String get comparisonPage => 'Сравнение';

  @override
  String get comparisonBottom => 'Ниже';

  @override
  String get comparisonLeft => 'Слева';

  @override
  String get comparisonMetric => 'Сходство';

  @override
  String get comparisonRight => 'Справа';

  @override
  String get comparisonTop => 'Выше';

  @override
  String galleryEmptyListBody(
      Object importIcon, Object mapLink, Object nearbyLink) {
    return 'Вы можете начать с поиска исторических фотографий [поблизости]($nearbyLink) или на [карте]($mapLink). Когда вы создадите реплику исторической фотографии, ваша фотография появится здесь. Также, можете нажать $importIcon, чтобы импортировать свои фотографии из файла, если вы ранее экспортировали их с помощью приложения';
  }

  @override
  String get galleryEmptyListTitle => 'Галерея пуста';

  @override
  String get galleryNoSearchResults => 'Нет результатов поиска';

  @override
  String get galleryRecentPictures => 'Просмотрено недавно';

  @override
  String get importError => 'Не удалось импортировать файл';

  @override
  String get importSuccessful => 'Файл успешно импортирован';

  @override
  String get searchBarHint => 'Поискать...';

  @override
  String get shareMenu => 'Как вы хотите поделиться?';

  @override
  String get shareMenuCancel => 'Отменить';

  @override
  String get shareMenuExport => 'Экспортировать данные';

  @override
  String get shareMenuImages => 'Делиться фотографиями';

  @override
  String shareMenuPublishTo(Object site) {
    return 'Опубликовать на $site';
  }

  @override
  String shareMenuUploadTo(Object site) {
    return 'Загрузить на $site';
  }

  @override
  String get uploadMenu => 'Что вы хотите загрузить?';

  @override
  String get uploadMenuCancel => 'Отменить';

  @override
  String get uploadMenuFile => 'Другой файл';

  @override
  String get uploadMenuFileAligned => 'Другой файл (Выравнять)';

  @override
  String get uploadMenuOriginal => 'Давнюю фотографию';

  @override
  String get uploadMenuOriginalAligned => 'Давнюю фотографию (Выравнять)';

  @override
  String get uploadMenuPicture => 'Свою фотографию';

  @override
  String get uploadMenuPictureAligned => 'Свою фотографию (Выравнять)';

  @override
  String uploadPage(Object site) {
    return 'Загрузить на $site';
  }
}
