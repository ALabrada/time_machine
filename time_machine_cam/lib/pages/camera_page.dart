import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera_camera/camera_camera.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_cam/controllers/photo_controller.dart';
import 'package:time_machine_cam/molecules/compass_view.dart';
import 'package:time_machine_net/time_machine_net.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.picture,
  });

  final Picture? picture;

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late PhotoController controller;

  @override
  void initState() {
    controller = PhotoController();
    super.initState();
    unawaited(controller.init());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = widget.picture;
    return Stack(
      children: [
        CameraCamera(
          resolutionPreset: ResolutionPreset.max,
          enableAudio: false,
          onFile: (_) { },
        ),
        if (picture != null)
          Opacity(
            opacity: 0.5,
            child: CachedNetworkImage(imageUrl: picture.url),
          ),
        Positioned(
          top: 16,
          left: 16,
          child: StreamBuilder(
            stream: controller.position,
            builder: (context, snapshot) {
              return CompassView(
                position: snapshot.data,
                target: picture?.location,
              );
            },
          ),
        ),
      ],
    );
  }
}
