import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'config_localizations_en.dart';
import 'config_localizations_es.dart';
import 'config_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ConfigLocalizations
/// returned by `ConfigLocalizations.of(context)`.
///
/// Applications need to include `ConfigLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/config_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ConfigLocalizations.localizationsDelegates,
///   supportedLocales: ConfigLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ConfigLocalizations.supportedLocales
/// property.
abstract class ConfigLocalizations {
  ConfigLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ConfigLocalizations of(BuildContext context) {
    return Localizations.of<ConfigLocalizations>(context, ConfigLocalizations)!;
  }

  static const LocalizationsDelegate<ConfigLocalizations> delegate =
      _ConfigLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('ru'),
  ];

  /// No description provided for @helpPage.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get helpPage;

  /// No description provided for @questionHowToFindPicturesBody.
  ///
  /// In en, this message translates to:
  /// **'You can find pictures either in your vicinity (**Nearby** tab) or in the map (**Map** tab). The application will load the pictures from online databases, so you will need an active internet connection. You can choose which databases to use, among other parameters, in the configuration (**Settings** tab).'**
  String get questionHowToFindPicturesBody;

  /// No description provided for @questionHowToFindPicturesTitle.
  ///
  /// In en, this message translates to:
  /// **'How to find historic pictures?'**
  String get questionHowToFindPicturesTitle;

  /// No description provided for @questionHowToImportPicturesBody.
  ///
  /// In en, this message translates to:
  /// **'When you select the option to import a photo, you will be asked to find the picture in your phone. When you select it, the photo will appear overlaid with the historic picture. Align the pictures as closely as possible, and then press the **Save** button. You will be taken to the **Comparison** page.'**
  String get questionHowToImportPicturesBody;

  /// No description provided for @questionHowToImportPicturesTitle.
  ///
  /// In en, this message translates to:
  /// **'How to import replicas of historic pictures?'**
  String get questionHowToImportPicturesTitle;

  /// No description provided for @questionHowToReplicatePictureBody.
  ///
  /// In en, this message translates to:
  /// **'Once you found a historic picture in your vicinity or in the map, you can either take a picture in the application, or import an existing picture from your phone. First, tap or long press the historic picture, and then select the desired option from the toolbar or context menu, accordingly.'**
  String get questionHowToReplicatePictureBody;

  /// No description provided for @questionHowToReplicatePictureTitle.
  ///
  /// In en, this message translates to:
  /// **'How to replicate an historic picture?'**
  String get questionHowToReplicatePictureTitle;

  /// No description provided for @questionHowToSharePicturesBody.
  ///
  /// In en, this message translates to:
  /// **'You can share a historic picture and its replica from the **Comparison** view, by pressing the corresponding button. The context menu allows publishing pictures in the [Re.Photos](https://www.re.photos) website, in our [Telegram channel](https://t.me/history_lens_app), among other methods. In order to publish to [Re.Photos](https://www.re.photos), you will be taken to their website and will have to complete the creation form, but first you will need to login to your account (or create an account if you haven`t one). \n\nIt is better to share the original versions of the historic pictures, obtained from their website, to avoid watermarks. You can access the website by selecting the historical picture and pressing the **Browser** button.'**
  String get questionHowToSharePicturesBody;

  /// No description provided for @questionHowToSharePicturesTitle.
  ///
  /// In en, this message translates to:
  /// **'How to share my pictures?'**
  String get questionHowToSharePicturesTitle;

  /// No description provided for @questionHowToTakePictureBody.
  ///
  /// In en, this message translates to:
  /// **'When you open the camera to take a picture, the historic picture will appear overlaid with the camera preview. If you are far from the location of the historic picture, the top left corner will show instructions to reach it. Then, align the historic picture with the camera preview as closely as possible and take the photo. When the picture is saved, you will be able to open the **Comparison** screen or continue taking pictures.'**
  String get questionHowToTakePictureBody;

  /// No description provided for @questionHowToTakePictureTitle.
  ///
  /// In en, this message translates to:
  /// **'How to take a picture in the application?'**
  String get questionHowToTakePictureTitle;

  /// No description provided for @questionWhatDataIsCollectedBody.
  ///
  /// In en, this message translates to:
  /// **'All the data collected by the application is stored locally in the phone. The data is shared only when you explicitly choose the share the pictures. The recorded photos will also contain their corresponding geo-coordinates.'**
  String get questionWhatDataIsCollectedBody;

  /// No description provided for @questionWhatDataIsCollectedTitle.
  ///
  /// In en, this message translates to:
  /// **'What data does the application collect on me?'**
  String get questionWhatDataIsCollectedTitle;

  /// No description provided for @questionWhatIsAppPurposeBody.
  ///
  /// In en, this message translates to:
  /// **'The application allows discovering historic pictures and recreating them, in order to compare them with the present. Then, you can share those pictures in [Re.Photos](https://www.re.photos) or in our [Telegram channel](https://t.me/history_lens_app).'**
  String get questionWhatIsAppPurposeBody;

  /// No description provided for @questionWhatIsAppPurposeTitle.
  ///
  /// In en, this message translates to:
  /// **'What is the purpose of the History Lens application?'**
  String get questionWhatIsAppPurposeTitle;

  /// No description provided for @sectionDataBases.
  ///
  /// In en, this message translates to:
  /// **'Picture DataBases'**
  String get sectionDataBases;

  /// No description provided for @sectionCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get sectionCamera;

  /// No description provided for @sectionInformation.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get sectionInformation;

  /// No description provided for @sectionMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get sectionMap;

  /// No description provided for @sectionSearchOptions.
  ///
  /// In en, this message translates to:
  /// **'Search Options'**
  String get sectionSearchOptions;

  /// No description provided for @settingGeocoder.
  ///
  /// In en, this message translates to:
  /// **'Address Database'**
  String get settingGeocoder;

  /// No description provided for @settingHelp.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get settingHelp;

  /// No description provided for @settingMapProvider.
  ///
  /// In en, this message translates to:
  /// **'Map Provider'**
  String get settingMapProvider;

  /// No description provided for @settingPictureRatio.
  ///
  /// In en, this message translates to:
  /// **'Picture Ratio'**
  String get settingPictureRatio;

  /// No description provided for @settingReferenceOpacity.
  ///
  /// In en, this message translates to:
  /// **'Reference Opacity'**
  String get settingReferenceOpacity;

  /// No description provided for @settingSearchBeginning.
  ///
  /// In en, this message translates to:
  /// **'Beginning (year)'**
  String get settingSearchBeginning;

  /// No description provided for @settingSearchEnd.
  ///
  /// In en, this message translates to:
  /// **'End (year)'**
  String get settingSearchEnd;
}

class _ConfigLocalizationsDelegate
    extends LocalizationsDelegate<ConfigLocalizations> {
  const _ConfigLocalizationsDelegate();

  @override
  Future<ConfigLocalizations> load(Locale locale) {
    return SynchronousFuture<ConfigLocalizations>(
      lookupConfigLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_ConfigLocalizationsDelegate old) => false;
}

ConfigLocalizations lookupConfigLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ConfigLocalizationsEn();
    case 'es':
      return ConfigLocalizationsEs();
    case 'ru':
      return ConfigLocalizationsRu();
  }

  throw FlutterError(
    'ConfigLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
