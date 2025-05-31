import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CameraToggleButton extends StatelessWidget {
  const CameraToggleButton({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.black.withOpacity(0.6),
        child: getIconByPlatform(),
      ),
    );
  }

  Widget getIconByPlatform() {
    if (kIsWeb) {
      return Icon(Icons.flip_camera_android,
        color: Colors.white,
      );
    }
    if (Platform.isAndroid) {
      return Icon(Icons.flip_camera_android,
        color: Colors.white,
      );
    } else {
      return Icon(Icons.flip_camera_ios,
        color: Colors.white,
      );
    }
  }
}
