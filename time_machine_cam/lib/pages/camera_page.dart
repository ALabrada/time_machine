import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/l10n/cam_localizations_en.dart';
import 'package:time_machine_cam/molecules/camera_flash_button.dart';
import 'package:time_machine_cam/molecules/camera_toggle_button.dart';
import 'package:time_machine_cam/molecules/camera_trigger_button.dart';
import 'package:time_machine_cam/molecules/camera_zoom_button.dart';
import 'package:time_machine_cam/molecules/rotated_view.dart';
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
          appBar: AppBar(
            title: Text(picture?.description ?? ""),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
          ),
          body: _buildContent(picture: picture),
        );
      },
    );
  }

  Widget _buildContent({Picture? picture}) {
    return CameraAwesomeBuilder.custom(
      saveConfig: SaveConfig.photo(),
      sensorConfig: SensorConfig.single(
        aspectRatio: controller.cameraMode,
      ),
      enablePhysicalButton: true,
      previewFit: CameraPreviewFit.contain,
      onMediaCaptureEvent: (capture) {
        capture.captureRequest.when(
          single: (r) => _savePicture(
            file: r.file,
            original: picture,
          ),
        );
      },
      builder: (state, preview) {
        return state.when(
          onPreparingCamera: (state) => const Center(
            child: CircularProgressIndicator(),
          ),
          onPhotoMode: (state) => _buildUI(
              state: state,
              picture: picture,
              previewSize: preview.previewSize
          ),
        );
      },
    );
  }

  Widget _buildUI({
    required PhotoCameraState state,
    Picture? picture,
    Size? previewSize,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (picture != null)
          RotatedView(
            child: _buildOverlay(picture),
          ),
        Container(
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.only(bottom: 126),
          child: AwesomeOrientedWidget(
            child: CameraZoomButton(state: state),
          ),
        ),
        Container(
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.only(bottom: 42, left: 64),
          child: AwesomeOrientedWidget(
            child: AwesomeFlashButton(state: state),
          ),
        ),
        Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 32),
          child: AwesomeOrientedWidget(
            child: AwesomeCaptureButton(state: state),
          ),
        ),
        Container(
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.only(bottom: 42, right: 64),
          child: AwesomeOrientedWidget(
            child: AwesomeCameraSwitchButton(
              scale: 1,
              state: state,
            ),
          ),
        ),
        Container(
          alignment: Alignment.topLeft,
          padding: EdgeInsets.only(top: 16, left: 16),
          child: AwesomeOrientedWidget(
            child: _buildCompass(picture),
          ),
        ),
      ],
    );
  }

  Widget _buildCompass(Picture? picture) {
    return StreamBuilder(
      stream: CombineLatestStream.combine2(controller.position, controller.heading, (x, y) => (position: x, heading: y)),
      builder: (context, snapshot) {
        return CompassView(
          position: snapshot.data?.position,
          heading: snapshot.data?.heading,
          target: picture?.location,
        );
      },
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

  Future<Picture?> _loadPicture() async {
    final id = widget.pictureId;
    if (id == null) {
      return null;
    }
    final db = context.read<DatabaseService>();
    final picture = await db.createRepository<Picture>().getById(id);
    return picture;
  }

  Future<void> _savePicture({
    XFile? file,
    Picture? original,
  }) async {
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CamLocalizations.of(context).couldNotTakePhoto),
        backgroundColor: Theme.of(context).primaryColor,
      ));
      return;
    }
    final db = context.read<DatabaseService>();
    final screenSize = await _screenSize;
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

  Future<Size> get _screenSize async {
    final size = MediaQuery.sizeOf(context);
    final orientation = await CamerawesomePlugin.getNativeOrientation()?.first;
    if (orientation == null || orientation == CameraOrientations.portrait_up || orientation == CameraOrientations.portrait_down) {
      return size;
    }
    return Size(size.height, size.width);
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