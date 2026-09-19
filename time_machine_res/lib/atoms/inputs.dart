import 'package:flutter/material.dart';
import '../foundation/color_foundation.dart';
import '../foundation/typography_foundation.dart';

InputDecorationTheme formFieldDecoration(BuildContext context) => InputDecorationTheme(
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(
      color: textFieldBorderColor(context),
      width: 1,
    ),
    borderRadius: BorderRadius.all(Radius.circular(4)),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(
      color: textFieldFocusedColor(context),
      width: 0,
    ),
    borderRadius: BorderRadius.all(Radius.circular(4)),
  ),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  fillColor: textFieldBackgroundColor(context),
  filled: true,
  hintStyle: TextStyle(
    color: textFieldHintColor(context),
    fontFamily: textFieldFontFamily,
    fontSize: textFieldFontSize,
    fontWeight: textFieldFontWeight,
  ),
);

InputDecorationTheme searchFieldDecoration(BuildContext context) => InputDecorationTheme(
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(
      color: Colors.transparent,
      width: 0,
    ),
    borderRadius: BorderRadius.all(Radius.circular(4)),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(
      color: Colors.transparent,
      width: 0,
    ),
    borderRadius: BorderRadius.all(Radius.circular(4)),
  ),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  fillColor: textFieldBackgroundColor(context),
  filled: true,
  hintStyle: TextStyle(
    color: textFieldHintColor(context),
    fontFamily: textFieldFontFamily,
    fontSize: textFieldFontSize,
    fontWeight: textFieldFontWeight,
  ),
);