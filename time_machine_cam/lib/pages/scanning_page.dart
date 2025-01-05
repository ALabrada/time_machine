import 'dart:async';
import 'package:ar_location_view/ar_location_view.dart';
import 'package:flutter/material.dart';
import 'package:image_preview/image_preview.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_cam/controllers/ar_controller.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_cam/molecules/annotation_view.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:go_router/go_router.dart';

class ScanningPage extends StatefulWidget {
  const ScanningPage({
    super.key,
    this.maxDistanceInMeters=1000,
  });

  final double maxDistanceInMeters;

  @override
  _ScanningPageState createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  late ARController arController;

  @override
  void initState() {
    arController = ARController(
      maxDistanceInMeters: widget.maxDistanceInMeters,
      networkService: context.read<NetworkService>(),
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
            // showDebugInfoSensor: false,
            annotations: snapshot.data ?? [],
            maxVisibleDistance: widget.maxDistanceInMeters,
            annotationViewBuilder: (context, annotation) {
              final model = annotation as PictureAnnotation;
              return AnnotationView(
                key: ValueKey(annotation.uid),
                annotation: model,
                onTapPicture: () => _showImage(model.picture),
                onTap: () => unawaited(_takePicture(model.picture)),
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

  Future<void> _takePicture(Picture model) async {
    final db = context.read<DatabaseService?>();
    final newModel = await db?.savePicture(model);
    final id = newModel?.localId;
    if (mounted && id != null) {
      context.go('/camera?pictureId=$id');
    }
  }
}
