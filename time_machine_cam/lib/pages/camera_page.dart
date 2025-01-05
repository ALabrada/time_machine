import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera_camera/camera_camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_cam/controllers/photo_controller.dart';
import 'package:time_machine_cam/molecules/compass_view.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.pictureId,
  });

  final int? pictureId;

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
    return FutureBuilder(
      future: _loadPicture(),
      builder: (context, snapshot) {
        final picture = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(picture?.description ?? ""),
          ),
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              CameraCamera(
                resolutionPreset: ResolutionPreset.max,
                enableAudio: false,
                onFile: (file) => _savePicture(file, original: picture),
              ),
              if (picture != null)
                Opacity(
                  opacity: 0.5,
                  child: CachedNetworkImage(imageUrl: picture.url),
                ),
              Positioned(
                top: 68,
                left: 16,
                child: StreamBuilder(
                  stream: CombineLatestStream.combine2(controller.position, controller.heading, (x, y) => (position: x, heading: y)),
                  builder: (context, snapshot) {
                    return CompassView(
                      position: snapshot.data?.position,
                      heading: snapshot.data?.heading,
                      target: picture?.location,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Picture?> _loadPicture() async {
    final id = widget.pictureId;
    if (id == null) {
      return null;
    }
    final db = context.read<DatabaseService>();
    return await db.createRepository<Picture>().getById(id);
  }

  Future<void> _savePicture(XFile file, {Picture? original}) async {
    final db = context.read<DatabaseService>();
    await db.createRecord(
      file: file,
      original: original,
      position: controller.position.valueOrNull,
      heading: controller.heading.valueOrNull,
    );
  }
}
