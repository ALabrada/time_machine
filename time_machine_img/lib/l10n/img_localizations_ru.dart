// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'img_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class ImgLocalizationsRu extends ImgLocalizations {
  ImgLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get deleteCancel => 'Отменить';

  @override
  String get deleteConfirm => 'Удалить';

  @override
  String get deleteTitle => 'Удаление';

  @override
  String get deleteSubtitle => 'Вы уверены, что хотите удалить реплику?';

  @override
  String get errorLoadingPage => 'Не удалось подключиться к серверу';

  @override
  String get comparisonPage => 'Сравнение';

  @override
  String get comparisonBottom => 'Ниже';

  @override
  String get comparisonLeft => 'Слева';

  @override
  String get comparisonRight => 'Справа';

  @override
  String get comparisonTop => 'Выше';

  @override
  String get galleryEmptyList => 'Галерея пуста';

  @override
  String get galleryNoSearchResults => 'Нет результатов поиска';

  @override
  String get searchBarHint => 'Поискать...';

  @override
  String get shareMenu => 'Как вы хотите поделиться?';

  @override
  String get shareMenuCancel => 'Отменить';

  @override
  String get shareMenuImages => 'Делиться фотографиями';

  @override
  String shareMenuUploadTo(Object site) {
    return 'Загрузить на $site';
  }

  @override
  String get uploadMenu => 'Что вы хотите загрузить?';

  @override
  String get uploadMenuFile => 'Другой файл';

  @override
  String get uploadMenuOriginal => 'Давнюю фотографию';

  @override
  String get uploadMenuPicture => 'Свою фотографию';

  @override
  String uploadPage(Object site) {
    return 'Загрузить на $site';
  }
}
