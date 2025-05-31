import 'dart:async';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';

class CameraZoomButton extends StatelessWidget {
  const CameraZoomButton({
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
        return StreamBuilder(
          stream: sensorConfig.zoom$,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container();
            }
            return _buildButton(
              onTap: () => unawaited(_changeZoom(sensorConfig)),
              zoom: snapshot.requireData
            );
          },
        );
      },
    );
  }

  Widget _buildButton({
    VoidCallback? onTap,
    num zoom = 0,
  } ) {
    final percent = 100.0 * zoom;
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.black.withOpacity(0.6),
      child: IconButton(
        onPressed: onTap,
        icon: Center(
          child: Text(
            "${percent.toStringAsFixed(0)}%",
            style: TextStyle(
                color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Future<void> _changeZoom(SensorConfig config) async {
    var zoom = config.zoom;
    if (zoom + 0.25 <= 1) {
      zoom += 0.5;
    } else {
      zoom = 0;
    }
    await config.setZoom(zoom);
  }
}
