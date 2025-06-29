import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'res_localizations_en.dart';
import 'res_localizations_es.dart';
import 'res_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ResLocalizations
/// returned by `ResLocalizations.of(context)`.
///
/// Applications need to include `ResLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/res_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ResLocalizations.localizationsDelegates,
///   supportedLocales: ResLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the ResLocalizations.supportedLocales
/// property.
abstract class ResLocalizations {
  ResLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ResLocalizations of(BuildContext context) {
    return Localizations.of<ResLocalizations>(context, ResLocalizations)!;
  }

  static const LocalizationsDelegate<ResLocalizations> delegate =
      _ResLocalizationsDelegate();

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
  /// **'Take replica of the picture'**
  String get menuActionCamera;

  /// No description provided for @menuActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get menuActionCancel;

  /// No description provided for @menuActionImport.
  ///
  /// In en, this message translates to:
  /// **'Import replica of the picture'**
  String get menuActionImport;

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
}

class _ResLocalizationsDelegate
    extends LocalizationsDelegate<ResLocalizations> {
  const _ResLocalizationsDelegate();

  @override
  Future<ResLocalizations> load(Locale locale) {
    return SynchronousFuture<ResLocalizations>(lookupResLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_ResLocalizationsDelegate old) => false;
}

ResLocalizations lookupResLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ResLocalizationsEn();
    case 'es':
      return ResLocalizationsEs();
    case 'ru':
      return ResLocalizationsRu();
  }

  throw FlutterError(
      'ResLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
