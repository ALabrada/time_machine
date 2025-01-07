import 'package:time_machine_res/atoms/labels.dart';
import 'package:time_machine_res/foundation/color_foundation.dart';
import 'package:time_machine_res/foundation/typography_foundation.dart';
import 'package:flutter/material.dart';

const buttonTextStyle = TextStyle(
  fontFamily: buttonFontFamily,
  fontSize: buttonFontSize,
  fontWeight: buttonFontWeight,
);

final primaryButtonLightStyle = FilledButton.styleFrom(
  backgroundColor: primaryButtonLightBackgroundColor,
  foregroundColor: primaryButtonLightForegroundColor,
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

final primaryButtonDarkStyle = FilledButton.styleFrom(
  backgroundColor: primaryButtonDarkBackgroundColor,
  foregroundColor: primaryButtonDarkForegroundColor,
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

final primaryButtonAlertStyle = FilledButton.styleFrom(
  backgroundColor: Colors.red,
  foregroundColor: primaryButtonDarkForegroundColor,
  minimumSize: const Size(54.0, 54.0),
  padding: const EdgeInsets.all(16),
  textStyle: buttonTextStyle,
);

final tabNormalStyle = IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: tabNormalColor,
  padding: const EdgeInsets.all(5),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.zero),
    side: BorderSide(color: Colors.transparent, width: 0),
  ),
);

final tabSelectedStyle = IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: tabSelectedColor,
  padding: const EdgeInsets.all(5),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.zero),
    side: BorderSide(color: Colors.transparent, width: 0),
  ),
);

final tertiaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: tertiaryButtonBackgroundColor,
  foregroundColor: tertiaryButtonForegroundColor,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle,
);

final selectedTertiaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: selectedTertiaryButtonBackgroundColor,
  foregroundColor: selectedTertiaryButtonForegroundColor,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle.apply(color: selectedTertiaryButtonForegroundColor),
);

final invalidTertiaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: invalidTertiaryButtonBackgroundColor,
  foregroundColor: invalidTertiaryButtonForegroundColor,
  disabledBackgroundColor: invalidTertiaryButtonBackgroundColor,
  disabledForegroundColor: invalidTertiaryButtonForegroundColor,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: tertiaryLabelStyle.apply(color: selectedTertiaryButtonForegroundColor),
);

final textButtonStyle = TextButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: textButtonForegroundColor,
  padding: const EdgeInsets.all(16),
  textStyle: const TextStyle(
    fontFamily: buttonFontFamily,
    fontSize: buttonFontSize,
    fontWeight: buttonFontWeight,
  ),
);