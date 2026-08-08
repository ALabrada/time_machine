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

class TabletCameraPageState extends State<TabletCameraPage> {
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
  late Future<Picture?> _loadPictureFuture;

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  CameraDescription? _currentCamera;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  FlashMode _flashMode = FlashMode.auto;

  @override
  void initState() {
    controller = PhotoController(
      cacheService: context.read(),
      configurationService: context.read(),
      databaseService: context.read(),
      networkService: context.read(),
    );
    _loadPictureFuture = controller.loadPicture(widget.pictureId);
    super.initState();
    unawaited(controller.init());
    unawaited(_initCamera());
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
    audioPlayer.dispose();
    controller.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) {
        return;
      }
      setState(() {
        _cameras = cameras;
        _currentCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
      });
      await _selectCamera(_currentCamera);
    } catch (e) {
      debugPrint('TabletCameraPage error: $e');
    }
  }

  Future<void> _selectCamera(CameraDescription? description) async {
    if (description == null) {
      return;
    }
    final previous = _camera;
    _camera = null;
    await previous?.dispose();
    if (!mounted) {
      return;
    }
    final camera = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await camera.initialize();
    } catch (e) {
      debugPrint('TabletCameraPage init error: $e');
      await camera.dispose();
      return;
    }
    if (!mounted) {
      await camera.dispose();
      return;
    }
    _minZoom = await camera.getMinZoomLevel();
    _maxZoom = await camera.getMaxZoomLevel();
    setState(() {
      _camera = camera;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != _currentCamera?.lensDirection,
      orElse: () => _cameras.first,
    );
    setState(() {
      _currentCamera = next;
    });
    await _selectCamera(next);
  }

  Future<void> _changeZoom() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return;
    }
    if (_zoomLevel + 0.25 <= _maxZoom) {
      _zoomLevel += 0.5;
    } else {
      _zoomLevel = _minZoom;
    }
    setState(() {});
    await camera.setZoomLevel(_zoomLevel);
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return;
    }
    final current = _flashMode;
    final next = switch (current) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() {
      _flashMode = next;
    });
    await camera.setFlashMode(next);
  }

  Future<void> _takePicture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return;
    }
    controller.isProcessing.value = true;
    unawaited(_playShutterSound());
    try {
      final file = await camera.takePicture();
      await _savePicture(file: file, camera: camera);
    } catch (e) {
      debugPrint('TabletCameraPage capture error: $e');
      await _savePicture(file: null, camera: camera);
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
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildPreview(camera: camera, picture: picture);
  }

  static const bool _debugOrientation = true;

  Widget _buildPreview({required CameraController camera, Picture? picture}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final aspect = camera.value.aspectRatio;
        final windowOrientation =
            area.width > area.height ? 'landscape' : 'portrait';
        final v = camera.value;
        final deviceTurns = _quarterTurns(v.deviceOrientation);
        final correctionTurns = (deviceTurns - _sensorCorrectionTurns) % 4;
        final pluginNetTurns = (1 - deviceTurns) % 4;
        final netTurns = (correctionTurns + pluginNetTurns) % 4;
        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        final contentAspect = netTurns.isOdd ? 1 / aspect : aspect;
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
        if (_debugOrientation) {
          debugPrint(
            'TabletCameraDebug area=${area.width.round()}x${area.height.round()} '
            'window=$windowOrientation device=${v.deviceOrientation} '
            'devTurns=$deviceTurns correction=$correctionTurns '
            'pluginNet=$pluginNetTurns net=$netTurns '
            'preview=${v.previewSize} aspect=${aspect.toStringAsFixed(3)} '
            'contentAspect=${contentAspect.toStringAsFixed(3)} '
            'box=$_previewBox',
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_debugOrientation)
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _sensorCorrectionTurns = (_sensorCorrectionTurns + 1) % 4;
                    });
                  },
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      '${windowOrientation.toUpperCase()} tap→corr\n'
                      'dev=${v.deviceOrientation}\n'
                      'corr=$_sensorCorrectionTurns turns=$correctionTurns\n'
                      'net=$netTurns\n'
                      'prev=$v.previewSize\n'
                      'asp=${aspect.toStringAsFixed(3)}\n'
                      'casp=${contentAspect.toStringAsFixed(3)}\n'
                      'box=${_previewBox?.width.round()}x${_previewBox?.height.round()}',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
                ),
              ),
            Center(
              child: isAndroid
                  ? AspectRatio(
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
                    )
                  : CameraPreview(camera, child: pictureOverlay),
            ),
            Container(
              alignment: Alignment.bottomCenter,
              padding: EdgeInsets.only(bottom: 126),
              child: _buildZoomButton(camera),
            ),
            Container(
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.only(bottom: 42, left: 64),
              child: _buildFlashButton(camera),
            ),
            Container(
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 32),
              child: _buildTrigger(),
            ),
            Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.only(bottom: 42, right: 64),
              child: _buildSwitchButton(),
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

  Widget _buildZoomButton(CameraController camera) {
    final percent = 100.0 * _zoomLevel;
    return _roundButton(
      onTap: _changeZoom,
      icon: Center(
        child: Text(
          "${percent.toStringAsFixed(0)}%",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildFlashButton(CameraController camera) {
    return _roundButton(
      onTap: _toggleFlash,
      icon: Icon(
        _flashModeIcon(_flashMode),
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
      onTap: _switchCamera,
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

  /// Number of clockwise quarter turns the camera plugin (ImageReader path)
  /// adds on top of the raw 16:9 frame for this device, i.e.
  /// `(sensorOrientationDegrees - displayRotationDegrees * facingSign) / 90`.
  ///
  /// Measured on the Pixel Tablet emulator: sensor = 90, display = ROTATION_0,
  /// back camera -> 1. This compensates the plugin's rotation so the preview
  /// renders upright relative to the landscape window. Tunable at runtime via
  /// the debug overlay until the preview is upright.
  int _sensorCorrectionTurns = 0;

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
