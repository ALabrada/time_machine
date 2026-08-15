import 'package:time_machine_res/foundation/color_foundation.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_res/tokens/colors.dart';

const colorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: primary01,
  onPrimary: label01,
  secondary: accent01,
  onSecondary: label03,
  surface: background01,
  onSurface: label01,
  error: warn,
  onError: label03,
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: primary01,
  onPrimary: label03Dark,
  secondary: accent01Dark,
  onSecondary: label01Dark,
  surface: background01Dark,
  onSurface: label01Dark,
  error: warnDark,
  onError: label01Dark,
);

DividerThemeData dividerTheme(BuildContext context) => DividerThemeData(
  color: dividerColor(context),
  space: 1,
  thickness: 1,
  indent: 0,
  endIndent: 0
);