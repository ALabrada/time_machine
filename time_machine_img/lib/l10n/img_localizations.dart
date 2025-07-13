import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'img_localizations_en.dart';
import 'img_localizations_es.dart';
import 'img_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ImgLocalizations
/// returned by `ImgLocalizations.of(context)`.
///
/// Applications need to include `ImgLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/img_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ImgLocalizations.localizationsDelegates,
///   supportedLocales: ImgLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the ImgLocalizations.supportedLocales
/// property.
abstract class ImgLocalizations {
  ImgLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ImgLocalizations of(BuildContext context) {
    return Localizations.of<ImgLocalizations>(context, ImgLocalizations)!;
  }

  static const LocalizationsDelegate<ImgLocalizations> delegate =
      _ImgLocalizationsDelegate();

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
    Locale('ru')
  ];

  /// No description provided for @creationMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Create replica'**
  String get creationMenuTitle;

  /// No description provided for @creationMenuActionCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a picture'**
  String get creationMenuActionCamera;

  /// No description provided for @creationMenuActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get creationMenuActionCancel;

  /// No description provided for @creationMenuActionImport.
  ///
  /// In en, this message translates to:
  /// **'Import a picture from the library'**
  String get creationMenuActionImport;

  /// No description provided for @deleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get deleteCancel;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirm;

  /// No description provided for @deleteManySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the replicas?'**
  String get deleteManySubtitle;

  /// No description provided for @deleteManyTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting {count}'**
  String deleteManyTitle(Object count);

  /// No description provided for @deleteOneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the replica?'**
  String get deleteOneSubtitle;

  /// No description provided for @deleteOneTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get deleteOneTitle;

  /// No description provided for @errorLoadingPage.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server'**
  String get errorLoadingPage;

  /// No description provided for @comparisonPage.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get comparisonPage;

  /// No description provided for @comparisonBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get comparisonBottom;

  /// No description provided for @comparisonLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get comparisonLeft;

  /// No description provided for @comparisonMetric.
  ///
  /// In en, this message translates to:
  /// **'Similarity'**
  String get comparisonMetric;

  /// No description provided for @comparisonRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get comparisonRight;

  /// No description provided for @comparisonTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get comparisonTop;

  /// No description provided for @galleryEmptyListBody.
  ///
  /// In en, this message translates to:
  /// **'You can start by looking for historical pictures [nearby]({nearbyLink}) or in the [map]({mapLink}). When you replicate a historic picture, your photo will appear here. You can also press {importIcon} to import your pictures from a file, if you previously exported them using the App.'**
  String galleryEmptyListBody(
      Object importIcon, Object mapLink, Object nearbyLink);

  /// No description provided for @galleryEmptyListTitle.
  ///
  /// In en, this message translates to:
  /// **'The gallery is empty'**
  String get galleryEmptyListTitle;

  /// No description provided for @galleryNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No search results'**
  String get galleryNoSearchResults;

  /// No description provided for @galleryRecentPictures.
  ///
  /// In en, this message translates to:
  /// **'Viewed recently'**
  String get galleryRecentPictures;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Could not import the provided file'**
  String get importError;

  /// No description provided for @importSuccessful.
  ///
  /// In en, this message translates to:
  /// **'File imported successfully'**
  String get importSuccessful;

  /// No description provided for @searchBarHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchBarHint;

  /// No description provided for @shareMenu.
  ///
  /// In en, this message translates to:
  /// **'How to share?'**
  String get shareMenu;

  /// No description provided for @shareMenuCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shareMenuCancel;

  /// No description provided for @shareMenuExport.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get shareMenuExport;

  /// No description provided for @shareMenuImages.
  ///
  /// In en, this message translates to:
  /// **'Share images'**
  String get shareMenuImages;

  /// No description provided for @shareMenuPublishTo.
  ///
  /// In en, this message translates to:
  /// **'Publish in {site}'**
  String shareMenuPublishTo(Object site);

  /// No description provided for @shareMenuUploadTo.
  ///
  /// In en, this message translates to:
  /// **'Upload to {site}'**
  String shareMenuUploadTo(Object site);

  /// No description provided for @uploadMenu.
  ///
  /// In en, this message translates to:
  /// **'What to upload?'**
  String get uploadMenu;

  /// No description provided for @uploadMenuCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uploadMenuCancel;

  /// No description provided for @uploadMenuFile.
  ///
  /// In en, this message translates to:
  /// **'Another file'**
  String get uploadMenuFile;

  /// No description provided for @uploadMenuFileAligned.
  ///
  /// In en, this message translates to:
  /// **'Another file (Aligned)'**
  String get uploadMenuFileAligned;

  /// No description provided for @uploadMenuOriginal.
  ///
  /// In en, this message translates to:
  /// **'Old picture'**
  String get uploadMenuOriginal;

  /// No description provided for @uploadMenuOriginalAligned.
  ///
  /// In en, this message translates to:
  /// **'Old picture (Aligned)'**
  String get uploadMenuOriginalAligned;

  /// No description provided for @uploadMenuPicture.
  ///
  /// In en, this message translates to:
  /// **'My picture'**
  String get uploadMenuPicture;

  /// No description provided for @uploadMenuPictureAligned.
  ///
  /// In en, this message translates to:
  /// **'My picture (Aligned)'**
  String get uploadMenuPictureAligned;

  /// No description provided for @uploadPage.
  ///
  /// In en, this message translates to:
  /// **'Upload to {site}'**
  String uploadPage(Object site);
}

class _ImgLocalizationsDelegate
    extends LocalizationsDelegate<ImgLocalizations> {
  const _ImgLocalizationsDelegate();

  @override
  Future<ImgLocalizations> load(Locale locale) {
    return SynchronousFuture<ImgLocalizations>(lookupImgLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_ImgLocalizationsDelegate old) => false;
}

ImgLocalizations lookupImgLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ImgLocalizationsEn();
    case 'es':
      return ImgLocalizationsEs();
    case 'ru':
      return ImgLocalizationsRu();
  }

  throw FlutterError(
      'ImgLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
