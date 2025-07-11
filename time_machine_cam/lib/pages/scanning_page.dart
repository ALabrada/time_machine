import 'dart:async';
import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:ar_location_view/ar_location_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_cam/l10n/cam_localizations.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_cam/controllers/ar_controller.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_cam/molecules/annotation_view.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:go_router/go_router.dart';
import 'package:time_machine_res/molecules/context_menu.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ScanningPage extends StatefulWidget {
  const ScanningPage({
    super.key,
    this.maxDistanceInMeters=1500,
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
      configurationService: context.read<ConfigurationService>(),
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
            showDebugInfoSensor: !kReleaseMode,
            annotations: snapshot.data ?? [],
            maxVisibleDistance: widget.maxDistanceInMeters,
            annotationViewBuilder: (context, annotation) {
              final model = annotation as PictureAnnotation;
              return AnnotationView(
                key: ValueKey(annotation.uid),
                annotation: model,
                onLongPress: () => unawaited(_showMenu(model.picture)),
                onTapPicture: () => unawaited(_showImage(model.picture)),
              );
            },
            onLocationChange: (p) {
              unawaited(arController.loadPictures(p));
            },
          );
        }
    );
  }

  Future<void> _showImage(Picture? model) async {
    if (model == null) {
      return;
    }
    final db = context.read<DatabaseService?>();
    final newModel = await db?.savePicture(model);
    final id = newModel?.localId;
    if (mounted && id != null) {
      context.go('/picture/$id');
    }
  }

  Future<void> _showMenu(Picture model) async {
    await context.showContextMenu(
      model: model,
      databaseService: context.read(),
      navigateTo: (url) {
        if (!url.startsWith('/')) {
          launchUrlString(url);
        } else if (mounted) {
          context.go(url);
        }
      },
      shareFile: (path) {
        Share.shareXFiles([
          XFile(path),
        ], text: model.text);
      }
    );
  }
}
