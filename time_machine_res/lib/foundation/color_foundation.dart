import 'package:flutter/material.dart';
import 'package:time_machine_res/tokens/colors.dart';

Color _lightOrDark(BuildContext context, {
  required Color light,
  required Color dark,
}) => Theme.of(context).brightness == Brightness.dark ? dark : light;

Color bodyColor(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color dividerColor(BuildContext context) =>
    _lightOrDark(context, light: Color(0xFFBDC5CD), dark: dividerColorDark);

Color h1Color(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color h2Color(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color h3Color(BuildContext context) =>
    _lightOrDark(context, light: label02, dark: label02Dark);

Color secondaryLabelColor(BuildContext context) =>
    _lightOrDark(context, light: label02, dark: label02Dark);

Color textFieldBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: gray01, dark: gray01Dark);

Color textFieldBorderColor(BuildContext context) =>
    _lightOrDark(context, light: gray02, dark: gray02Dark);

Color textFieldDisabledColor(BuildContext context) =>
    _lightOrDark(context, light: gray03, dark: gray03Dark);

Color textFieldFocusedColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color textFieldHintColor(BuildContext context) =>
    _lightOrDark(context, light: gray05, dark: gray05Dark);

Color textFieldTextColor(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color textFieldLabelColor(BuildContext context) =>
    _lightOrDark(context, light: gray05, dark: gray05Dark);

Color tertiaryLabelColor(BuildContext context) =>
    _lightOrDark(context, light: gray05, dark: gray05Dark);

Color backgroundColor(BuildContext context) =>
    _lightOrDark(context, light: background01, dark: background01Dark);

Color secondaryBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: background02, dark: background02Dark);

Color themeColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color primaryAccentColor(BuildContext context) =>
    _lightOrDark(context, light: accent01, dark: accent01Dark);

Color secondaryAccentColor(BuildContext context) =>
    _lightOrDark(context, light: accent02, dark: accent02Dark);

Color primaryLabelColor(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color shadowColor(BuildContext context) =>
    _lightOrDark(context, light: gray06, dark: gray06Dark);

Color invalidTertiaryButtonBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: warn, dark: warnDark);

Color invalidTertiaryButtonForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: background01, dark: label03Dark);

Color menuIconColor(BuildContext context) =>
    _lightOrDark(context, light: gray04, dark: gray04Dark);

Color menuLabelColor(BuildContext context) =>
    _lightOrDark(context, light: label01, dark: label01Dark);

Color primaryButtonLightBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: background01, dark: background01Dark);

Color primaryButtonLightForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color primaryButtonDarkBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color primaryButtonDarkForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: background01, dark: label03Dark);

Color selectedTertiaryButtonBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color selectedTertiaryButtonForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: background01, dark: label03Dark);

Color tabNormalColor(BuildContext context) =>
    _lightOrDark(context, light: gray04, dark: gray04Dark);

Color tabSelectedColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);

Color tertiaryButtonBackgroundColor(BuildContext context) =>
    _lightOrDark(context, light: gray01, dark: gray01Dark);

Color tertiaryButtonForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: gray05, dark: gray05Dark);

Color textButtonForegroundColor(BuildContext context) =>
    _lightOrDark(context, light: primary01, dark: primary01Dark);