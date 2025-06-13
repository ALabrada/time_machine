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
