import 'package:time_machine_res/foundation/color_foundation.dart';
import 'package:time_machine_res/foundation/typography_foundation.dart';
import 'package:flutter/material.dart';

TextStyle bodyStyle(BuildContext context) => TextStyle(
  color: bodyColor(context),
  fontFamily: bodyFontFamily,
  fontSize: bodyFontSize,
  fontWeight: bodyFontWeight,
);

TextStyle h1Style(BuildContext context) => TextStyle(
  color: h1Color(context),
  fontFamily: h1FontFamily,
  fontSize: h1FontSize,
  fontWeight: h1FontWeight,
);

TextStyle h2Style(BuildContext context) => TextStyle(
  color: h2Color(context),
  fontFamily: h2FontFamily,
  fontSize: h2FontSize,
  fontWeight: h2FontWeight,
);

TextStyle h3Style(BuildContext context) => TextStyle(
  color: h3Color(context),
  fontFamily: h3FontFamily,
  fontSize: h3FontSize,
  fontWeight: h3FontWeight,
);

TextStyle secondaryLabelStyle(BuildContext context) => TextStyle(
  color: secondaryLabelColor(context),
  fontFamily: secondaryLabelFontFamily,
  fontSize: secondaryLabelFontSize,
  fontWeight: secondaryLabelFontWeight,
);

TextStyle tertiaryLabelStyle(BuildContext context) => TextStyle(
  color: tertiaryLabelColor(context),
  fontFamily: tertiaryLabelFontFamily,
  fontSize: tertiaryLabelFontSize,
  fontWeight: tertiaryLabelFontWeight,
);

TextStyle textFieldLabelStyle(BuildContext context) => TextStyle(
  color: textFieldLabelColor(context),
  fontFamily: textFieldLabelFontFamily,
  fontSize: textFieldLabelFontSize,
  fontWeight: textFieldLabelFontWeight,
);
