import 'package:time_machine_res/foundation/color_foundation.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_res/tokens/colors.dart';

final colorScheme = ColorScheme(
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

const dividerTheme = DividerThemeData(
  color: dividerColor,
  space: 1,
  thickness: 1,
  indent: 0,
  endIndent: 0
);