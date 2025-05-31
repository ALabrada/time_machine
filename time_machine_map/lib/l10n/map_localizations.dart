import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'map_localizations_en.dart';
import 'map_localizations_es.dart';
import 'map_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of MapLocalizations
/// returned by `MapLocalizations.of(context)`.
///
/// Applications need to include `MapLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/map_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: MapLocalizations.localizationsDelegates,
///   supportedLocales: MapLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the MapLocalizations.supportedLocales
/// property.
abstract class MapLocalizations {
  MapLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static MapLocalizations of(BuildContext context) {
    return Localizations.of<MapLocalizations>(context, MapLocalizations)!;
  }

  static const LocalizationsDelegate<MapLocalizations> delegate =
      _MapLocalizationsDelegate();

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

  /// No description provided for @menuTitle.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get menuTitle;

  /// No description provided for @menuActionCamera.
  ///
  /// In en, this message translates to:
  /// **'Take picture'**
  String get menuActionCamera;

  /// No description provided for @menuActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get menuActionCancel;

  /// No description provided for @menuActionOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get menuActionOpenSource;

  /// No description provided for @menuActionShare.
  ///
  /// In en, this message translates to:
  /// **'Share picture'**
  String get menuActionShare;

  /// No description provided for @menuActionView.
  ///
  /// In en, this message translates to:
  /// **'Show picture'**
  String get menuActionView;

  /// No description provided for @searchBarHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchBarHint;
}

class _MapLocalizationsDelegate
    extends LocalizationsDelegate<MapLocalizations> {
  const _MapLocalizationsDelegate();

  @override
  Future<MapLocalizations> load(Locale locale) {
    return SynchronousFuture<MapLocalizations>(lookupMapLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_MapLocalizationsDelegate old) => false;
}

MapLocalizations lookupMapLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return MapLocalizationsEn();
    case 'es':
      return MapLocalizationsEs();
    case 'ru':
      return MapLocalizationsRu();
  }

  throw FlutterError(
      'MapLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
