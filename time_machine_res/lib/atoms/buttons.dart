import 'package:time_machine_res/atoms/labels.dart';
import 'package:time_machine_res/foundation/color_foundation.dart';
import 'package:time_machine_res/foundation/typography_foundation.dart';
import 'package:flutter/material.dart';

const buttonTextStyle = TextStyle(
  fontFamily: buttonFontFamily,
  fontSize: buttonFontSize,
  fontWeight: buttonFontWeight,
);

ButtonStyle primaryButtonLightStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: primaryButtonLightBackgroundColor(context),
  foregroundColor: primaryButtonLightForegroundColor(context),
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

ButtonStyle primaryButtonDarkStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: primaryButtonDarkBackgroundColor(context),
  foregroundColor: primaryButtonDarkForegroundColor(context),
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

ButtonStyle primaryButtonAlertStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: Colors.red,
  foregroundColor: primaryButtonDarkForegroundColor(context),
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

ButtonStyle tabNormalStyle(BuildContext context) => IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: tabNormalColor(context),
  padding: const EdgeInsets.all(5),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.zero),
    side: BorderSide(color: Colors.transparent, width: 0),
  ),
);

ButtonStyle tabSelectedStyle(BuildContext context) => IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: tabSelectedColor(context),
  padding: const EdgeInsets.all(5),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.zero),
    side: BorderSide(color: Colors.transparent, width: 0),
  ),
);

ButtonStyle tertiaryButtonStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: tertiaryButtonBackgroundColor(context),
  foregroundColor: tertiaryButtonForegroundColor(context),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle(context),
);

ButtonStyle selectedTertiaryButtonStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: selectedTertiaryButtonBackgroundColor(context),
  foregroundColor: selectedTertiaryButtonForegroundColor(context),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle(context).apply(color: selectedTertiaryButtonForegroundColor(context)),
);

ButtonStyle invalidTertiaryButtonStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: invalidTertiaryButtonBackgroundColor(context),
  foregroundColor: invalidTertiaryButtonForegroundColor(context),
  disabledBackgroundColor: invalidTertiaryButtonBackgroundColor(context),
  disabledForegroundColor: invalidTertiaryButtonForegroundColor(context),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle(context).apply(color: selectedTertiaryButtonForegroundColor(context)),
);

ButtonStyle textButtonStyle(BuildContext context) => TextButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: textButtonForegroundColor(context),
  padding: const EdgeInsets.all(16),
  textStyle: const TextStyle(
    fontFamily: buttonFontFamily,
    fontSize: buttonFontSize,
    fontWeight: buttonFontWeight,
  ),
);