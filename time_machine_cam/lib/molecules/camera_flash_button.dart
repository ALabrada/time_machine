import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CameraFlashButton extends StatelessWidget {
  const CameraFlashButton({
    super.key,
    required this.state,
  });

  final CameraState state;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SensorConfig>(
      // Listen to the current SensorConfig. It might change when switching between front and back cameras.
      stream: state.sensorConfig$,
      builder: (_, sensorConfigSnapshot) {
        if (!sensorConfigSnapshot.hasData) {
          return const SizedBox.shrink();
        }
        final sensorConfig = sensorConfigSnapshot.requireData;
        return StreamBuilder<FlashMode>(
          // Listen to the currently selected flash mode
          stream: sensorConfig.flashMode$,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container();
            }
            return _buildButton(
              // Build your button differently based on the current Flash mode, with different icons for instance
              flashMode: snapshot.requireData,
              onTap: () => sensorConfig.switchCameraFlash(),
            );
          },
        );
      },
    );
  }

  Widget _buildButton({
    VoidCallback? onTap,
    FlashMode flashMode = FlashMode.none,
  } ) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.black.withOpacity(0.6),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          _flashModeIcon(flashMode),
          color: Colors.white,
        ),
      ),
    );
  }

  IconData _flashModeIcon(FlashMode flashMode) {
    switch (flashMode) {
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.none:
        return Icons.flash_off;
      case FlashMode.on:
        return FontAwesomeIcons.lightbulb;
    }
  }
}
