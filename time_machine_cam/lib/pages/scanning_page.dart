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
import 'package:url_launcher/url_launcher_string.dart';

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
    final title = model.description;
    final site = model.site;
    await showAdaptiveActionSheet<Picture>(
      context: context,
      title: title == null ? null : Text(title),
      cancelAction: CancelAction(
        title: Text(CamLocalizations.of(context).menuActionCancel),
      ),
      actions: [
        BottomSheetAction(
          leading: Icon(Icons.image_rounded),
          title: Text(CamLocalizations.of(context).menuActionView),
          onPressed: (context) {
            _showImage(model);
            context.pop();
          },
        ),
        BottomSheetAction(
          leading: Icon(Icons.camera_alt),
          title: Text(CamLocalizations.of(context).menuActionCamera),
          onPressed: (context) {
            _takePicture(model);
            context.pop();
          },
        ),
        if (site != null && site.isNotEmpty)
          BottomSheetAction(
            leading: Icon(Icons.open_in_browser),
            title: Text(CamLocalizations.of(context).menuActionOpenSource),
            onPressed: (context) {
              _openSite(site);
              context.pop();
            },
          ),
        BottomSheetAction(
          leading: Icon(Icons.share),
          title: Text(CamLocalizations.of(context).menuActionShare),
          onPressed: (context) {
            unawaited(_sharePicture(model));
            context.pop();
          },
        ),
      ],
    );
  }

  void _openSite(String site) {
    unawaited(launchUrlString(site));
  }

  Future<void> _sharePicture(Picture picture) async {
    final file = await CachedNetworkImageProvider.defaultCacheManager.getSingleFile(picture.url);
    await Share.shareXFiles([
      XFile(file.path),
    ], text: picture.text);
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
