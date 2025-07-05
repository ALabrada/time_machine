// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'config_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ConfigLocalizationsEn extends ConfigLocalizations {
  ConfigLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get helpPage => 'FAQs';

  @override
  String questionHowToFindPicturesBody(
    String nearbyIcon,
    String mapIcon,
    String settingsIcon,
  ) {
    return 'You can find pictures either in your vicinity ($nearbyIcon **Nearby** tab) or in the map ($mapIcon **Map** tab). The application will load the pictures from online databases, so you will need an active internet connection. You can choose which databases to use, among other parameters, in the configuration ($settingsIcon **Settings** tab).';
  }

  @override
  String get questionHowToFindPicturesTitle => 'How to find historic pictures?';

  @override
  String questionHowToImportPicturesBody(String saveIcon) {
    return 'When you select the option to import a photo, you will be asked to find the picture in your phone. When you select it, the photo will appear overlaid with the historic picture. Align the pictures as closely as possible, and then press the $saveIcon **Save** button. You will be taken to the **Comparison** page.';
  }

  @override
  String get questionHowToImportPicturesTitle =>
      'How to import replicas of historic pictures?';

  @override
  String get questionHowToReplicatePictureBody =>
      'Once you found a historic picture in your vicinity or in the map, you can either take a picture in the application, or import an existing picture from your phone. First, tap or long press the historic picture, and then select the desired option from the toolbar or context menu, accordingly.';

  @override
  String get questionHowToReplicatePictureTitle =>
      'How to replicate an historic picture?';

  @override
  String questionHowToSharePicturesBody(
    String telegramChannel,
    String browserIcon,
  ) {
    return 'You can share a historic picture and its replica from the **Comparison** view, by pressing the corresponding button. The context menu allows publishing pictures in the [Re.Photos](https://www.re.photos) website, in our [Telegram channel]($telegramChannel), among other methods. In order to publish to [Re.Photos](https://www.re.photos), you will be taken to their website and will have to complete the creation form, but first you will need to login to your account (or create an account if you haven`t one). \n\nIt is better to share the original versions of the historic pictures, obtained from their website, to avoid watermarks. You can access the website by selecting the historical picture and pressing the $browserIcon **Browser** button.';
  }

  @override
  String get questionHowToSharePicturesTitle => 'How to share my pictures?';

  @override
  String get questionHowToTakePictureBody =>
      'When you open the camera to take a picture, the historic picture will appear overlaid with the camera preview. If you are far from the location of the historic picture, the top left corner will show instructions to reach it. Then, align the historic picture with the camera preview as closely as possible and take the photo. When the picture is saved, you will be able to open the **Comparison** screen or continue taking pictures.';

  @override
  String get questionHowToTakePictureTitle =>
      'How to take a picture in the application?';

  @override
  String get questionWhatDataIsCollectedBody =>
      'All the data collected by the application is stored locally in the phone. The data is shared only when you explicitly choose the share the pictures. The recorded photos will also contain their corresponding geo-coordinates.';

  @override
  String get questionWhatDataIsCollectedTitle =>
      'What data does the application collect on me?';

  @override
  String questionWhatIsAppPurposeBody(String telegramChannel) {
    return 'The application allows discovering historic pictures and recreating them, in order to compare them with the present. Then, you can share those pictures in [Re.Photos](https://www.re.photos) or in our [Telegram channel]($telegramChannel).';
  }

  @override
  String get questionWhatIsAppPurposeTitle =>
      'What is the purpose of the History Lens application?';

  @override
  String get sectionDataBases => 'Picture DataBases';

  @override
  String get sectionCamera => 'Camera';

  @override
  String get sectionInformation => 'Information';

  @override
  String get sectionMap => 'Map';

  @override
  String get sectionSearchOptions => 'Search Options';

  @override
  String get settingGeocoder => 'Address Database';

  @override
  String get settingHelp => 'FAQs';

  @override
  String get settingMapProvider => 'Map Provider';

  @override
  String get settingPictureRatio => 'Picture Ratio';

  @override
  String get settingReferenceOpacity => 'Reference Opacity';

  @override
  String get settingSearchBeginning => 'Beginning (year)';

  @override
  String get settingSearchEnd => 'End (year)';
}
