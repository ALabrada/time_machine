import 'package:flutter/material.dart';
import '../foundation/color_foundation.dart';
import '../foundation/typography_foundation.dart';

const searchFieldDecoration = InputDecorationTheme(
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
  fillColor: textFieldBackgroundColor,
  filled: true,
  hintStyle: TextStyle(
    color: textFieldHintColor,
    fontFamily: textFieldFontFamily,
    fontSize: textFieldFontSize,
    fontWeight: textFieldFontWeight,
  ),
);