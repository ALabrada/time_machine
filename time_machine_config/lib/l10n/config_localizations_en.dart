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
  String questionHowToFindPicturesBodyDesktop(
    String mapIcon,
    String settingsIcon,
  ) {
    return 'You can find pictures in the map ($mapIcon **Map** tab). The application will load the pictures from online databases, so you will need an active internet connection. You can choose which databases to use, among other parameters, in the configuration ($settingsIcon **Settings** tab).';
  }

  @override
  String get questionHowToFindPicturesTitle => 'How to find historic pictures?';

  @override
  String questionHowToImportPicturesBody(String saveIcon) {
    return 'When you select the option to import a photo, you will be asked to find the picture on your device. When you select it, the photo will appear overlaid with the historic picture. Align the pictures as closely as possible, and then press the $saveIcon **Save** button. You will be taken to the **Comparison** page.';
  }

  @override
  String get questionHowToImportPicturesTitle =>
      'How to import replicas of historic pictures?';

  @override
  String get questionHowToReplicatePictureBody =>
      'Once you found a historic picture in your vicinity or in the map, you can either take a picture in the application, or import an existing picture from your device. First, tap or long press the historic picture, and then select the desired option from the toolbar or context menu, accordingly.';

  @override
  String get questionHowToReplicatePictureBodyDesktop =>
      'Once you found a historic picture in the map, you can either take a picture in the application, or import an existing picture from your computer. First, tap or long press the historic picture, and then select the desired option from the toolbar or context menu, accordingly.';

  @override
  String get questionHowToReplicatePictureTitle =>
      'How to replicate an historic picture?';

  @override
  String questionHowToSharePicturesBody(
    String telegramChannel,
    String browserIcon,
  ) {
    return 'You can share a historic picture and its replica from the **Comparison** view, by pressing the corresponding button. The context menu allows publishing pictures in the [Re.Photos](https://www.re.photos) website, in our [Telegram channel]($telegramChannel), among other methods. In order to publish to [Re.Photos](https://www.re.photos), you will be taken to their website and will have to complete the creation form, but first you will need to login to your account (or create an account if you don\'t have one). \n\nIt is better to share the original versions of the historic pictures, obtained from their website, to avoid watermarks. You can access the website by selecting the historical picture and pressing the $browserIcon **Browser** button.';
  }

  @override
  String questionHowToSharePicturesBodyDesktop(
    String telegramChannel,
    String browserIcon,
  ) {
    return 'You can save a historic picture or its replica by opening it and pressing the corresponding button, or by selecting the option in the context menu. The context menu also allows exporting the data and publishing pictures in the [Re.Photos](https://www.re.photos) website or in our [Telegram channel]($telegramChannel). In order to publish to [Re.Photos](https://www.re.photos), you will be taken to their website and will have to complete the creation form, but first you will need to login to your account (or create an account if you don\'t have one). \n\nIt is better to save the original versions of the historic pictures, obtained from their website, to avoid watermarks. You can access the website by selecting the historical picture and pressing the $browserIcon **Browser** button.';
  }

  @override
  String get questionHowToSharePicturesTitle => 'How to share my pictures?';

  @override
  String get questionHowToSharePicturesTitleDesktop =>
      'How to save my pictures?';

  @override
  String get questionHowToTakePictureBody =>
      'When you open the camera to take a picture, the historic picture will appear overlaid with the camera preview. If you are far from the location of the historic picture, the top left corner will show instructions to reach it. Then, align the historic picture with the camera preview as closely as possible and take the photo. When the picture is saved, you will be able to open the **Comparison** screen or continue taking pictures.';

  @override
  String get questionHowToTakePictureBodyDesktop =>
      'When you open the camera to take a picture, the historic picture will appear overlaid with the camera preview. Align the historic picture with the camera preview as closely as possible and take the photo. When the picture is saved, you will be able to open the **Comparison** screen or continue taking pictures.';

  @override
  String get questionHowToTakePictureTitle =>
      'How to take a picture in the application?';

  @override
  String get questionWhatDataIsCollectedBody =>
      'All the data collected by the application is stored locally on the device. The data is shared only when you explicitly choose to share the pictures. The recorded photos will also contain their corresponding geo-coordinates.';

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
  String get sectionAppearance => 'Appearance';

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
  String get settingVolumeButton => 'Volume Button';

  @override
  String get settingVolumeButtonDescription =>
      'Take a picture by pressing the volume keys';

  @override
  String get settingSearchBeginning => 'Beginning (year)';

  @override
  String get settingSearchEnd => 'End (year)';

  @override
  String get cloudPageTitle => 'Cloud';

  @override
  String get cloudPageProvider => 'Provider';

  @override
  String get cloudPageProviderSelect => 'Select a provider';

  @override
  String get cloudPageChangeProvider => 'Change provider';

  @override
  String get settingCloud => 'Cloud';

  @override
  String get sectionSync => 'Synchronization';

  @override
  String get cloudPageProviderNotSelected => 'No cloud provider selected.';

  @override
  String get cloudPageProviderUnavailable =>
      'The selected cloud provider is not available.';

  @override
  String get cloudPageLoadingConnecting => 'Connecting…';

  @override
  String get cloudPageLoadingAuthenticating => 'Authenticating…';

  @override
  String get cloudPageLoadingSynchronizing => 'Synchronizing…';

  @override
  String get cloudPageLoadingDeactivating => 'Deactivating…';

  @override
  String get cloudPageStatus => 'Status';

  @override
  String get cloudPageStatusActive => 'Active';

  @override
  String get cloudPageStatusInactive => 'Inactive';

  @override
  String get cloudPageAuthSection => 'Authentication';

  @override
  String get cloudPageAuthSignedIn => 'Signed in';

  @override
  String get cloudPageAuthSignedOut => 'Not signed in';

  @override
  String get cloudPageAuthSuccess => 'Signed in.';

  @override
  String get cloudPageAuthFailed => 'Authentication failed.';

  @override
  String get cloudPageEmail => 'Email';

  @override
  String get cloudPagePassword => 'Password';

  @override
  String get cloudPageSignIn => 'Sign in';

  @override
  String get cloudPageSignInAnonymously => 'Sign in anonymously';

  @override
  String get cloudPageSignOut => 'Sign out';

  @override
  String get cloudPageActivate => 'Activate';

  @override
  String get cloudPageActivationSuccess => 'Cloud activated.';

  @override
  String get cloudPageActivationFailed =>
      'Activation failed. Sign in to the provider first.';

  @override
  String get cloudPageDeactivate => 'Deactivate';

  @override
  String get cloudPageDeactivationSuccess => 'Cloud deactivated.';

  @override
  String get cloudPageDeactivationFailed => 'Deactivation failed.';

  @override
  String get cloudPageServerUrl => 'Server URL';

  @override
  String get cloudPageLoginName => 'Login name';

  @override
  String get cloudPagePasswordHint =>
      'Use an app password (recommended) or your account password. An app password is created in Personal settings → Security → App passwords.';

  @override
  String get cloudPageServerUrlInvalid => 'Enter a valid server URL.';

  @override
  String get cloudPageFieldRequired => 'Required.';

  @override
  String get settingThemeMode => 'Theme';

  @override
  String get settingThemeModeDark => 'Dark';

  @override
  String get settingThemeModeLight => 'Light';

  @override
  String get settingThemeModeSystem => 'System';

  @override
  String get sectionTimelapse => 'Timelapse';

  @override
  String get settingTimelapseFrameSize => 'Frame Size';

  @override
  String get settingTimelapseFps => 'Frames per second';
}
