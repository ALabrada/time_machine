import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minimum width (logical pixels) above which the app uses the
/// tablet-optimized layout (side navigation rail, unlocked orientations).
const double tabletBreakpoint = 600;

/// Platform channel exposing the OS's own notion of a tablet.
const MethodChannel _deviceChannel =
    MethodChannel('com.fakegem.historylens/device');

bool? _osTablet;
Future<bool?>? _osTabletQuery;

/// Queries the OS for the tablet flag and caches the answer.
///
/// Phones and tablets differ, from this app's point of view, in whether the
/// OS allows the screen orientation to be locked, and that is an OS
/// decision, not a screen size. Android answers with the `sw600dp` resource
/// bucket, iOS with `userInterfaceIdiom`. Platforms without a signal
/// (desktop/web) cache a null, keeping the window-size fallback.
Future<bool?> prefetchOsTabletStatus() => _osTabletQuery ??= _queryOsTablet();

Future<bool?> _queryOsTablet() async {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return _osTablet = null;
  }
  try {
    return _osTablet = await _deviceChannel.invokeMethod<bool>('isTablet');
  } on MissingPluginException {
    return _osTablet = null;
  }
}

/// Whether the current device/window should use the tablet-optimized layout.
///
/// Decided by the OS when it reports a tablet (iOS iPad, Android `sw600dp`),
/// which is also what controls whether orientations can be locked. Otherwise
/// it falls back to the shortest side of the window, so small tablets are
/// recognized regardless of orientation and phones keep the classic layout.
bool isTabletLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide >= tabletBreakpoint ||
      (_osTablet ?? false);
}