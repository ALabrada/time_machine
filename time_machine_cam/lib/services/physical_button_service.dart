import 'dart:async';

import 'package:time_machine_config/time_machine_config.dart';
import 'package:vol_spotter/vol_spotter.dart';

enum PhysicalButton { volumeUp, volumeDown }

/// Streams physical volume-button presses so a camera page can act as a
/// shutter button.
///
/// Native listening starts only while there is at least one active
/// subscription and the [ConfigurationService.volumeButton] setting is
/// enabled, so the volume keys behave normally outside of the camera pages.
class PhysicalButtonService {
  PhysicalButtonService({
    required ConfigurationService configurationService,
  }) : _configurationService = configurationService;

  static const VolSpotter _volSpotter = VolSpotter();
  static const VolSpotterConfig _config =
      VolSpotterConfig(interceptVolumeEvents: true);

  final ConfigurationService _configurationService;

  StreamController<PhysicalButton>? _controller;
  StreamSubscription<ButtonEvent>? _subscription;

  Stream<PhysicalButton> get onButton {
    _controller ??= StreamController<PhysicalButton>.broadcast(
      onListen: _sync,
      onCancel: _sync,
    );
    return _controller!.stream;
  }

  bool get _isEnabled =>
      _configurationService.volumeButton ??
      ConfigurationService.defaultVolumeButton;

  void _sync() {
    if (_isEnabled && (_controller?.hasListener ?? false)) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (_subscription != null) {
      return;
    }
    _subscription = _volSpotter.buttonEvents
        .listen(_handleEvent, onError: (_) {});
    unawaited(_volSpotter.startListening(config: _config).onError((_, __) {}));
  }

  void _stop() {
    if (_subscription == null) {
      return;
    }
    _subscription?.cancel();
    _subscription = null;
    unawaited(_volSpotter.stopListening().onError((_, __) {}));
  }

  void _handleEvent(ButtonEvent event) {
    if (event.action is! ButtonPressed) {
      return;
    }
    final button = switch (event.button) {
      VolumeUpButton() => PhysicalButton.volumeUp,
      VolumeDownButton() => PhysicalButton.volumeDown,
      _ => null,
    };
    if (button != null) {
      _controller?.add(button);
    }
  }
}
