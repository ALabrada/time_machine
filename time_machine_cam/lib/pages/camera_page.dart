import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera_camera/camera_camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/l10n/cam_localizations_en.dart';
import 'package:time_machine_cam/molecules/camera_trigger_button.dart';
import 'package:time_machine_cam/services/database_service.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_cam/controllers/photo_controller.dart';
import 'package:time_machine_cam/molecules/compass_view.dart';
import 'package:time_machine_res/molecules/picture_frame.dart';

import '../l10n/cam_localizations.dart';

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
  final cameraKey = GlobalKey();
  late PhotoController controller;

  @override
  void initState() {
    controller = PhotoController(
      configurationService: context.read<ConfigurationService>(),
    );
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
          body: NativeDeviceOrientationReader(
            builder: (context) {
              return _buildContent(picture: picture);
            },
          ),
        );
      },
    );
  }

  Widget _buildContent({Picture? picture}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraCamera(
          key: cameraKey,
          resolutionPreset: ResolutionPreset.max,
          enableAudio: false,
          mode: controller.cameraMode,
          onFile: (file) => _savePicture(file, original: picture),
          onChangeCamera: (camera) => controller.camera.value = camera,
          onPreview: picture == null ? null : (context, child) => _buildPreview(context, child, _buildOverlay(picture)),
          triggerIcon: CameraTriggerButton(),
        ),
        // if (picture != null)
        //   SafeArea(
        //     child: _buildOverlay(picture),
        //   ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AppBar(
            title: Text(picture?.description ?? ""),
            backgroundColor: Theme.of(context).colorScheme.secondary.withAlpha(127),
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        RotatedContainer(
          alignment: Alignment.topLeft,
          padding: EdgeInsets.only(top: 76, left: 16),
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
    );
  }

  Widget _buildOverlay(Picture picture) {
    return IgnorePointer(
      child: Opacity(
        opacity: controller.pictureOpacity,
        child: CachedNetworkImage(
          imageUrl: picture.url,
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, Widget preview, Widget overlay) {
    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
        overlay,
      ],
    );
  }

  Future<Picture?> _loadPicture() async {
    final id = widget.pictureId;
    if (id == null) {
      return null;
    }
    final db = context.read<DatabaseService>();
    final picture = await db.createRepository<Picture>().getById(id);
    return picture;
  }

  Future<void> _savePicture(XFile file, {Picture? original}) async {
    final db = context.read<DatabaseService>();
    final screenSize = MediaQuery.sizeOf(context);
    print('Screen size: $screenSize');
    final record = await db.createRecord(
      file: file,
      original: original,
      position: controller.position.valueOrNull,
      heading: controller.heading.valueOrNull,
      width: screenSize.width,
      height: screenSize.height,
      cacheManager: CachedNetworkImageProvider.defaultCacheManager
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CamLocalizations.of(context).pictureAddedToGallery),
        backgroundColor: Theme.of(context).primaryColor,
        action: SnackBarAction(
          label: CamLocalizations.of(context).viewPicture,
          onPressed: () => context.go('/gallery/${record.localId}'),
        ),
      ));
    }
  }
}

extension GlobalKeyExtension on GlobalKey {
  Rect? get globalPaintBounds {
    final renderObject = currentContext?.findRenderObject();
    final matrix = renderObject?.getTransformTo(null);

    if (matrix != null && renderObject?.paintBounds != null) {
      final rect = MatrixUtils.transformRect(matrix, renderObject!.paintBounds);
      return rect;
    } else {
      return null;
    }
  }
}