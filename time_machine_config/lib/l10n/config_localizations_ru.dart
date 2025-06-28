// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class ConfigLocalizationsRu extends ConfigLocalizations {
  ConfigLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get helpPage => 'Частые Вопросы';

  @override
  String get questionHowToFindPicturesBody =>
      'Вы можете найти фотографии либо в непосредственной близости от вас (вкладка **Поблизости**), либо на карте (вкладка **Карта**). Приложение будет загружать фотографии из онлайн-баз данных, так что потребуется активное подключение к Интернету. Вы можете выбрать, какие базы данных использовать, среди прочих параметров, в конфигурации (вкладка **Настройки**).';

  @override
  String get questionHowToFindPicturesTitle =>
      'Как найти исторические фотографии?';

  @override
  String get questionHowToImportPicturesBody =>
      'Когда выберете опцию Импортировать фотографию, вам будет предложено найти ее в вашем телефоне. Когда вы выберете фотографию, она будет отображаться поверх исторической фотографии. Выровняйте изображения как можно ближе, а затем нажмите кнопку **Сохранить**. Тогда перейдете на страницу **Сравнения**.';

  @override
  String get questionHowToImportPicturesTitle =>
      'Как импортировать реплики исторических фотографий?';

  @override
  String get questionHowToReplicatePictureBody =>
      'После того, как нашли историческую фотографию в вашем близости или на карте, вы можете либо сделать снимок в приложении, либо импортировать существующую фотографию со своего телефона. Сначала коснитесь или долго нажимайте на историческую фотографию, а затем выберите желаемую  опцию на панели управления или в контекстном меню, соответственно.';

  @override
  String get questionHowToReplicatePictureTitle =>
      'Как воспроизвести историческую Фотографию?';

  @override
  String get questionHowToSharePicturesBody =>
      'Вы можете поделиться исторической фотографией и ее репликой в экране **Сравнения**, нажав соответствующую кнопку. Контекстное меню позволяет публиковать фотографии на веб-сайте [Re.Photos](https://www.re.photos), в нашем [Telegram-канале](https://t.me/history_lens_app) и другими способами. Чтобы опубликовать на [Re.Photos](https://www.re.photos), откроем их веб-сайт и надо будет заполнить форму создания, но сначала вам нужно будет войти в свой аккаунт (или создать аккаунт, если его нет). \n\nЛучше делиться оригинальными версиями исторических фотографий, полученных с их веб-сайта, чтобы избежать водяных знаков. Вы можете получить доступ к веб-сайту, выбрав историческую картинку и нажав кнопку **Браузер**.';

  @override
  String get questionHowToSharePicturesTitle =>
      'Как поделиться своими фотографиями?';

  @override
  String get questionHowToTakePictureBody =>
      'Когда вы откроете камеру, чтобы сделать фотографию, историческая фотография отображаться поверх сигнала камеры. Если вы находитесь далеко от местоположения исторической фотографии, в верхнем левом углу будут отображаться инструкции, как добраться до нее. Затем совместите историческую фотографию с камерой как можно точнее и сделайте снимок. Когда фотография сохранится, вы сможете открыть экран **Сравнения** или продолжить съемку.';

  @override
  String get questionHowToTakePictureTitle =>
      'Как сделать фотографию в приложении?';

  @override
  String get questionWhatDataIsCollectedBody =>
      'Все данные, собранные приложением, хранятся локально в телефоне. Данные публикуются только в том случае, если вы явно опубликуете фотографии. На записанных фотографиях также будут указаны соответствующие географические координаты.';

  @override
  String get questionWhatDataIsCollectedTitle =>
      'Какие данные обо мне собирает приложение?';

  @override
  String get questionWhatIsAppPurposeBody =>
      'Приложение позволяет находить исторические фотографии и воссоздавать их, чтобы сравнить с нынешними. Затем вы можете поделиться этими фотографиями в [Re.Photos](https://www.re.photos) или в нашем [Telegram-канале](https://t.me/history_lens_app).';

  @override
  String get questionWhatIsAppPurposeTitle =>
      'Какова цель приложения Линзы Истории?';

  @override
  String get sectionDataBases => 'Базы Данных Изображений';

  @override
  String get sectionCamera => 'Камера';

  @override
  String get sectionInformation => 'Информация';

  @override
  String get sectionMap => 'Карта';

  @override
  String get sectionSearchOptions => 'Параметры Поиска';

  @override
  String get settingGeocoder => 'База Данных Адресов';

  @override
  String get settingHelp => 'Частые Вопросы';

  @override
  String get settingMapProvider => 'Картографический Сервис';

  @override
  String get settingPictureRatio => 'Соотношение Сторон Изображения';

  @override
  String get settingReferenceOpacity => 'Прозрачность Эталона';

  @override
  String get settingSearchBeginning => 'Начало (год)';

  @override
  String get settingSearchEnd => 'Конец (года)';
}
