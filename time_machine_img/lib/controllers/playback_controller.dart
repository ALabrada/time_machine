import 'package:gif/gif.dart';

/// Controls playback of the timelapse GIF.
///
/// Extends [GifController] so the [Gif] widget renders through it, and owns
/// the play/pause, auto-replay and playback-speed state that [GifController]
/// itself does not provide.
class PlaybackController extends GifController {
  PlaybackController({
    required super.vsync,
    required Duration baseDuration,
  }) : _baseDuration = baseDuration;

  /// Requested playback duration before [playbackSpeed] scaling. Only used
  /// until the [Gif] widget populates [GifController.duration] with the real
  /// GIF duration.
  final Duration _baseDuration;

  bool _autoReplay = true;
  bool get autoReplay => _autoReplay;

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  void setAutoReplay(bool autoReplay) {
    _autoReplay = autoReplay;
    _restartPlayback();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _restartPlayback();
  }

  /// Pauses if playing, resumes otherwise.
  void togglePlayback() {
    if (isAnimating) {
      stop();
    } else {
      _start();
    }
  }

  /// Starts playback from the beginning.
  void play() {
    stop();
    value = 0.0;
    _start();
  }

  void _start() {
    if (_autoReplay) {
      repeat(
        min: 0,
        max: 1,
        reverse: true,
        period: _scaledDuration(),
      );
    } else {
      if (value >= 1.0) {
        value = 0.0;
      }
      repeat(
        min: 0,
        max: 1,
        reverse: false,
        count: 1,
        period: _scaledDuration(),
      );
    }
  }

  void _restartPlayback() {
    if (!isAnimating) {
      return;
    }
    stop();
    if (_autoReplay) {
      repeat(
        min: 0,
        max: 1,
        reverse: true,
        period: _scaledDuration(),
      );
    } else {
      if (value >= 1.0) {
        value = 0.0;
      }
      repeat(
        min: 0,
        max: 1,
        reverse: false,
        count: 1,
        period: _scaledDuration(),
      );
    }
  }

  Duration _scaledDuration() {
    final base = duration ?? _baseDuration;
    return Duration(
      milliseconds: (base.inMilliseconds / _playbackSpeed).round(),
    );
  }
}