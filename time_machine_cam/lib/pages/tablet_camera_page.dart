import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:go_router/go_router.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine_cam/controllers/photo_controller.dart';
import 'package:time_machine_cam/controllers/tablet_camera_controller.dart';
import 'package:time_machine_cam/molecules/camera_trigger_button.dart';
import 'package:time_machine_cam/molecules/compass_view.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../l10n/cam_localizations.dart';

class TabletCameraPage extends StatefulWidget {
  const TabletCameraPage({
    super.key,
    this.pictureId,
  });

  final int? pictureId;

  @override
  TabletCameraPageState createState() => TabletCameraPageState();
}

class TabletCameraPageState extends State<TabletCameraPage>
    with WidgetsBindingObserver {
  final audioPlayer = AudioPlayer()
    ..setAudioContext(AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build())
    ..setSource(AssetSource(
      'sounds/camera-shutter.mp3',
      mimeType: 'audio/mpeg',
    ))
    ..setReleaseMode(ReleaseMode.stop);
  late PhotoController controller;
  late TabletCameraController cameraController;
  late Future<Picture?> _loadPictureFuture;

  double _startZoom = 1.0;

  @override
  void initState() {
    cameraController = TabletCameraController();
    controller = PhotoController(
      cacheService: context.read(),
      configurationService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
      orientationStream: cameraController.onOrientationChanged(),
      applyHeadingOffset: false,
    );
    _loadPictureFuture = controller.loadPicture(widget.pictureId);
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(cameraController.loadDisplayRotation());
    unawaited(controller.init());
    unawaited(cameraController.init());
  }

  @override
  void didChangeMetrics() {
    unawaited(cameraController.loadDisplayRotation());
    super.didChangeMetrics();
  }

  @override
  void didUpdateWidget(covariant TabletCameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pictureId != oldWidget.pictureId) {
      _loadPictureFuture = controller.loadPicture(widget.pictureId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audioPlayer.dispose();
    controller.dispose();
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (!cameraController.isInitialized) {
      return;
    }
    controller.isProcessing.value = true;
    unawaited(_playShutterSound());
    try {
      final file = await cameraController.takePicture();
      await _savePicture(file: file, camera: cameraController.controller);
    } catch (e) {
      debugPrint('TabletCameraPage capture error: $e');
      await _savePicture(file: null, camera: cameraController.controller);
    } finally {
      controller.isProcessing.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadPictureFuture,
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
    if (kIsWeb) {
      return Center(
        child: Text(
          CamLocalizations.of(context).cameraNotSupported,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      );
    }
    return ListenableBuilder(
      listenable: cameraController,
      builder: (context, _) {
        if (!cameraController.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        final camera = cameraController.controller!;
        return ValueListenableBuilder<CameraValue>(
          valueListenable: camera,
          builder: (context, _, __) => _buildPreview(picture: picture),
        );
      },
    );
  }

  Widget _buildPreview({Picture? picture}) {
    final camera = cameraController.controller!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final aspect = camera.value.aspectRatio;
        final v = camera.value;
        final deviceTurns = _quarterTurns(v.deviceOrientation);
        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        final correctionTurns = isAndroid ? deviceTurns : 0;
        final bool portraitContent;
        if (isAndroid) {
          // The preview content one sees after the plugin's own rotation is the
          // raw sensor frame turned by `sensor - display * facingSign` quarter
          // turns. When odd, the upright content is portrait and the box must
          // swap its aspect. `display` is the Android default-display rotation
          // constant (real Surface rotation), which is what historically broke
          // the guess; we read it natively because a landscape window can still
          // report ROTATION_0 on natural-landscape displays.
          final sensorQuarterTurns = camera.description.sensorOrientation ~/ 90;
          final facingSign =
              camera.description.lensDirection == CameraLensDirection.back
                  ? -1
                  : 1;
          final displayQuarterTurns =
              cameraController.displayQuarterTurns ?? deviceTurns;
          final contentTurns =
              (sensorQuarterTurns - facingSign * displayQuarterTurns) % 4;
          portraitContent = contentTurns.isOdd;
        } else {
          // iOS and web deliver an upright, correctly-framed preview, so the
          // content aspect follows the device orientation, exactly like the
          // plugin's own CameraPreview widget.
          portraitContent =
              v.deviceOrientation == DeviceOrientation.portraitUp ||
              v.deviceOrientation == DeviceOrientation.portraitDown;
        }
        final contentAspect = portraitContent ? 1 / aspect : aspect;
        if (area.isFinite && !area.isEmpty) {
          _previewBox = _computePreviewBox(area, contentAspect);
        }
        final pictureOverlay = picture != null
            ? IgnorePointer(
                child: Opacity(
                  opacity: controller.pictureOpacity,
                  child: CachedImage(imageUrl: picture.url),
                ),
              )
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onScaleStart: (_) => _startZoom = cameraController.zoomLevel,
              onScaleUpdate: (details) {
                unawaited(cameraController.setZoom(_startZoom * details.scale));
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: contentAspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RotatedBox(
                        quarterTurns: correctionTurns,
                        child: camera.buildPreview(),
                      ),
                      if (pictureOverlay != null) pictureOverlay,
                    ],
                  ),
                ),
              ),
            ),
            Container(
              alignment: Alignment.bottomCenter,
              padding: EdgeInsets.only(bottom: 126),
              child: _buildZoomIndicator(),
            ),
            Container(
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 81),
                  _buildFlashButton(camera),
                  const SizedBox(width: 48),
                  _buildTrigger(),
                  const SizedBox(width: 48),
                  _buildSwitchButton(),
                  const SizedBox(width: 81),
                ],
              ),
            ),
            Container(
              alignment: Alignment.topLeft,
              padding: EdgeInsets.only(top: 16, left: 16),
              child: _buildCompass(picture),
            ),
          ],
        );
      },
    );
  }

  Widget _buildZoomIndicator() {
    final percent = 100.0 * cameraController.zoomLevel;
    return InkWell(
      onTap: () => unawaited(_toggleZoom()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          "${percent.toStringAsFixed(0)}%",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Future<void> _toggleZoom() async {
    final min = cameraController.minZoom;
    final max = cameraController.maxZoom;
    if (max <= min) {
      return;
    }
    // Cycle the zoom like the CameraPage's zoom button: step up by half the
    // [min, max] range until the top is reached, then reset to the minimum.
    var zoom = (cameraController.zoomLevel - min) / (max - min);
    if (zoom + 0.25 <= 1) {
      zoom += 0.5;
    } else {
      zoom = 0;
    }
    await cameraController.setZoom(zoom * (max - min) + min);
  }

  Widget _buildFlashButton(CameraController camera) {
    return _roundButton(
      onTap: cameraController.toggleFlash,
      icon: Icon(
        _flashModeIcon(cameraController.flashMode),
        color: Colors.white,
      ),
    );
  }

  IconData _flashModeIcon(FlashMode flashMode) {
    switch (flashMode) {
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  Widget _buildSwitchButton() {
    return _roundButton(
      onTap: cameraController.switchCamera,
      icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
    );
  }

  Widget _buildTrigger() {
    return StreamBuilder(
      stream: controller.isProcessing,
      initialData: false,
      builder: (context, snapshot) {
        if (snapshot.requireData) {
          return Container(
            height: 80,
            width: 80,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        return CameraTriggerButton(onPressed: _takePicture);
      },
    );
  }

  Widget _buildCompass(Picture? picture) {
    return StreamBuilder(
      stream: CombineLatestStream.combine2(controller.position,
          controller.heading, (x, y) => (position: x, heading: y)),
      builder: (context, snapshot) {
        return CompassView(
          position: snapshot.data?.position,
          heading: snapshot.data?.heading,
          target: picture?.location,
        );
      },
    );
  }

  Widget _roundButton({
    VoidCallback? onTap,
    required Widget icon,
  }) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.black.withValues(alpha: 0.6),
      child: IconButton(
        onPressed: onTap,
        icon: icon,
      ),
    );
  }

  Future<void> _playShutterSound() async {
    try {
      await audioPlayer.seek(Duration());
      await audioPlayer.resume();
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  Future<void> _savePicture({
    XFile? file,
    CameraController? camera,
  }) async {
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(CamLocalizations.of(context).couldNotTakePhoto),
        ));
      }
      return;
    }
    final box = _previewBox;
    final record = await controller
        .savePicture(
          file: file,
          height: box?.height ?? MediaQuery.sizeOf(context).height,
          width: box?.width ?? MediaQuery.sizeOf(context).width,
          orientation: _nativeOrientation(camera),
        )
        .onError((e, _) => null);

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

  Size? _previewBox;

  int _quarterTurns(DeviceOrientation? orientation) {
    switch (orientation) {
      case DeviceOrientation.landscapeRight:
        return 1;
      case DeviceOrientation.portraitDown:
        return 2;
      case DeviceOrientation.landscapeLeft:
        return 3;
      case DeviceOrientation.portraitUp:
      case null:
        return 0;
    }
  }

  Size? _computePreviewBox(Size area, double aspect) {
    final (_, _, w, h) = aspectFitRect(
      width: area.width,
      height: area.height,
      innerWidth: aspect,
      innerHeight: 1,
    );
    return Size(w, h);
  }

  NativeDeviceOrientation? _nativeOrientation(CameraController? camera) {
    final cameraOrientation = camera?.value.deviceOrientation;
    if (cameraOrientation == null) {
      return null;
    }
    switch (cameraOrientation) {
      case DeviceOrientation.portraitUp:
        return NativeDeviceOrientation.portraitUp;
      case DeviceOrientation.portraitDown:
        return NativeDeviceOrientation.portraitDown;
      case DeviceOrientation.landscapeLeft:
        return NativeDeviceOrientation.landscapeLeft;
      case DeviceOrientation.landscapeRight:
        return NativeDeviceOrientation.landscapeRight;
    }
  }
}
