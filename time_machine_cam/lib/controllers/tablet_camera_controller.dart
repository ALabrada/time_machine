import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

class TabletCameraController extends ChangeNotifier {
  static const MethodChannel _displayRotationChannel =
      MethodChannel('com.fakegem.historylens/orientation');

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  CameraDescription? _currentCamera;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  FlashMode _flashMode = FlashMode.auto;
  bool _disposed = false;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  CameraDescription? get currentCamera => _currentCamera;
  double get zoomLevel => _zoomLevel;
  double get maxZoom => _maxZoom;
  FlashMode get flashMode => _flashMode;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get canSwitchCamera => _cameras.length > 1;

  /// Quarter turns (0-3) of the Android default-display rotation, read natively
  /// via the `com.fakegem.historylens/orientation` channel. Only used on
  /// Android; null elsewhere, where the page falls back to `deviceOrientation`.
  int? get displayQuarterTurns => _displayQuarterTurns;
  int? _displayQuarterTurns;

  Future<void> loadDisplayRotation() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final rotation = await _displayRotationChannel
          .invokeMethod<int>('defaultDisplayRotation');
      final quarterTurns = _surfaceRotationQuarterTurns(rotation);
      if (_disposed || quarterTurns == _displayQuarterTurns) {
        return;
      }
      _displayQuarterTurns = quarterTurns;
      notifyListeners();
    } catch (_) {
      // Channel unavailable; rely on the deviceOrientation-derived fallback.
    }
  }

  int _surfaceRotationQuarterTurns(int? rotation) {
    return switch (rotation) {
      1 => 3, // Surface.ROTATION_90
      2 => 2, // Surface.ROTATION_180
      3 => 1, // Surface.ROTATION_270
      _ => 0,
    };
  }

  Future<void> init() async {
    try {
      final cameras = await availableCameras();
      if (_disposed) {
        return;
      }
      _cameras = cameras;
      _currentCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await selectCamera(_currentCamera);
    } catch (e) {
      debugPrint('TabletCameraController error: $e');
    }
  }

  Future<void> selectCamera(CameraDescription? description) async {
    if (description == null || _disposed) {
      return;
    }
    final previous = _controller;
    _controller = null;
    notifyListeners();
    await previous?.dispose();
    if (_disposed) {
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
      debugPrint('TabletCameraController init error: $e');
      await camera.dispose();
      return;
    }
    if (_disposed) {
      await camera.dispose();
      return;
    }
    _minZoom = await camera.getMinZoomLevel();
    _maxZoom = await camera.getMaxZoomLevel();
    _zoomLevel = _minZoom.clamp(1.0, _maxZoom).toDouble();
    _controller = camera;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (!canSwitchCamera) {
      return;
    }
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != _currentCamera?.lensDirection,
      orElse: () => _cameras.first,
    );
    if (identical(next, _currentCamera)) {
      return;
    }
    _currentCamera = next;
    await selectCamera(next);
  }

  Future<void> setZoom(double zoom) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) {
      return;
    }
    final next = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if (next == _zoomLevel) {
      return;
    }
    _zoomLevel = next;
    notifyListeners();
    await camera.setZoomLevel(next);
  }

  Future<void> toggleFlash() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) {
      return;
    }
    _flashMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    notifyListeners();
    await camera.setFlashMode(_flashMode);
  }

  Future<XFile> takePicture() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) {
      throw StateError('Camera is not initialized');
    }
    return camera.takePicture();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_controller?.dispose());
    super.dispose();
  }
}