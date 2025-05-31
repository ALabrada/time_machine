import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class RotatedView extends StatelessWidget {
  const RotatedView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CameraOrientations>(
      stream: CamerawesomePlugin.getNativeOrientation(),
      initialData: CameraOrientations.portrait_up,
      builder: (_, orientationSnapshot) {
        return _buildContainer(context, turns[orientationSnapshot.requireData]);
      },
    );
  }

  Widget _buildContainer(BuildContext context, int? quarterTurns) {
    if (quarterTurns == null) {
      return child;
    }
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: child,
    );
  }
}

Map<CameraOrientations, int> turns = {
  CameraOrientations.portrait_up: 0,
  CameraOrientations.landscape_right: 1,
  CameraOrientations.portrait_down: 2,
  CameraOrientations.landscape_left: 3,
};