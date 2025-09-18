import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final audioPlayer = AudioPlayer()
    ..setAudioContext(AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build())
    ..setSource(AssetSource('sounds/camera-shutter.mp3',
      mimeType: 'audio/mpeg',
    ))
    ..setReleaseMode(ReleaseMode.stop);
  late PhotoController controller;
  late Timer timer;

  @override
  void initState() {
    controller = PhotoController(
      cacheService: context.read(),
      configurationService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
    );
    super.initState();
    unawaited(controller.init());
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: controller.loadPicture(widget.pictureId),
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
      saveConfig: SaveConfig.photo(
        pathBuilder: (s) async => SingleCaptureRequest(controller.targetPath, s[0]),
        exifPreferences: ExifPreferences(saveGPSLocation: true),
      ),
      sensorConfig: SensorConfig.single(
        aspectRatio: controller.cameraMode,
      ),
      enablePhysicalButton: true,
      previewFit: CameraPreviewFit.contain,

      onMediaCaptureEvent: (capture) {
        switch (capture.status) {
          case MediaCaptureStatus.capturing:
            controller.isProcessing.value = true;
            unawaited(_playShutterSound());
          case MediaCaptureStatus.success:
            controller.isProcessing.value = false;
            capture.captureRequest.when(
              single: (r) => _savePicture(
                file: r.file,
              ),
            );
          case MediaCaptureStatus.failure:
            controller.isProcessing.value = false;
            _savePicture(
              file: null,
            );
        }
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
            child: _buildTrigger(state),
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

  Widget _buildTrigger(PhotoCameraState state) {
    return StreamBuilder(
      stream: controller.isProcessing,
      initialData: false,
      builder: (context, snapshot) {
        if (snapshot.requireData) {
          return Container(
            height: 80,
            width: 80,
            alignment: Alignment.center,
            child: CircularProgressIndicator(),
          );
        }
        return AwesomeCaptureButton(state: state);
      },
    );
  }

  Future<void> _playShutterSound() async {
    try {
      await audioPlayer.seek(Duration());
      await audioPlayer.resume();
    } catch (e) {
      print("Error playing sound: $e");
    }
  }

  Future<void> _savePicture({
    XFile? file,
  }) async {
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(CamLocalizations.of(context).couldNotTakePhoto),
        ));
      }
      return;
    }
    final screenSize = _screenSize;
    final record = await controller.savePicture(
      file: file,
      height: screenSize.height,
      width: screenSize.width,
    ).onError((e, _) => null);

    if (!mounted) {
      return;
    }

    if (record != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CamLocalizations.of(context).pictureAddedToGallery),
        action: SnackBarAction(
          label: CamLocalizations.of(context).viewPicture,
          onPressed: () => context.go('/gallery/${record.localId}'),
        ),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(CamLocalizations.of(context).couldNotTakePhoto),
      ));
    }
  }

  Size get _screenSize {
    final size = MediaQuery.sizeOf(context);
    final orientation = controller.orientation.valueOrNull;
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