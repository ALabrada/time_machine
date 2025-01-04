import 'dart:async';
import 'package:ar_location_view/ar_location_view.dart';
import 'package:flutter/material.dart';
import 'package:image_preview/image_preview.dart';
import 'package:time_machine_cam/controllers/ar_controller.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_cam/molecules/annotation_view.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.db,
    this.net,
    this.maxDistanceInMeters=1000,
  });

  final DatabaseService? db;
  final NetworkService? net;
  final double maxDistanceInMeters;

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late ARController arController;

  @override
  void initState() {
    arController = ARController(
      maxDistanceInMeters: widget.maxDistanceInMeters,
      networkService: widget.net,
    );
    super.initState();
  }

  @override
  void dispose() {
    arController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: arController.annotations,
        builder: (context, snapshot) {
          return ArLocationWidget(
            showDebugInfoSensor: false,
            annotations: snapshot.data ?? [],
            maxVisibleDistance: widget.maxDistanceInMeters,
            annotationViewBuilder: (context, annotation) {
              final model = annotation as PictureAnnotation;
              return AnnotationView(
                key: ValueKey(annotation.uid),
                annotation: model,
                onTap: () => _showImage(model.picture),
              );
            },
            onLocationChange: (p) {
              unawaited(arController.loadPictures(p));
            },
          );
        }
    );
  }

  void _showImage(Picture? model) {
    if (model == null) {
      return;
    }
    openImagePage(
      Navigator.of(context),
      imgUrl: model.url,
    );
  }
}
