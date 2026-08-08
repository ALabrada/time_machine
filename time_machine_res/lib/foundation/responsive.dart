import 'package:flutter/material.dart';

/// Minimum width (logical pixels) above which the app uses the
/// tablet-optimized layout (side navigation rail, unlocked orientations).
const double tabletBreakpoint = 600;

/// Whether the current device/screen should use the tablet-optimized layout.
///
/// Phones (narrow screens) keep the classic layout regardless, so the
/// adaptive behavior never changes their experience.
bool isTabletLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= tabletBreakpoint;
}