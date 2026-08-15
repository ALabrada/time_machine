import 'dart:async';
import 'package:ar_location_view/ar_location_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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

import '../l10n/cam_localizations.dart';

class ScanningPage extends StatefulWidget {
  const ScanningPage({
    super.key,
    this.maxDistanceInMeters=1500,
  });

  final double maxDistanceInMeters;

  @override
  ScanningPageState createState() => ScanningPageState();
}

class ScanningPageState extends State<ScanningPage> {
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
            errorBuilder: (context, error) {
              final l10n = CamLocalizations.of(context);
              final message = switch (error) {
                ArCameraError.authorizationRequired =>
                  l10n.arCameraAuthorizationRequired,
                ArCameraError.authorizationDenied =>
                  l10n.arCameraAuthorizationDenied,
                ArCameraError.initializationFailed =>
                  l10n.arCameraInitializationError,
              };
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              );
            },
            showDebugInfoSensor: !kReleaseMode,
            annotations: snapshot.data ?? [],
            maxVisibleDistance: widget.maxDistanceInMeters,
            annotationViewBuilder: _buildAnnotation,
            onLocationChange: (p) {
              unawaited(arController.loadPictures(p));
            },
          );
        }
    );
  }

  Widget _buildAnnotation(BuildContext context, ArAnnotation annotation) {
    final model = annotation as PictureAnnotation;
    return FutureBuilder(
      future: arController.fetchPicture(model.picture),
      builder: (context, snapshot) {
        final picture = snapshot.data;
        if (picture == null) {
          return CircularProgressIndicator();
        }
        return AnnotationView(
          key: ValueKey(annotation.uid),
          annotation: model,
          onLongPress: () => unawaited(_showMenu(model.picture)),
          onTapPicture: () => unawaited(_showImage(model.picture)),
        );
      },
    );
  }

  Future<void> _showImage(Picture? model) async {
    if (model == null) {
      return;
    }
    final db = context.read<DatabaseService?>();
    final fetchedModel = await arController.fetchPicture(model);
    if (fetchedModel == null) {
      return;
    }
    final savedModel = await db?.savePicture(model);
    final id = savedModel?.localId;
    if (mounted && id != null) {
      context.go('/picture/$id');
    }
  }

  Future<void> _showMenu(Picture model) async {
    final fetchedModel = await arController.fetchPicture(model);
    if (fetchedModel == null || !mounted) {
      return;
    }
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
      shareFile: (path) async {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(path)],
          text: model.text,
        ));
      }
    );
  }
}
