import 'dart:typed_data';

import 'package:time_machine_db/time_machine_db.dart';

abstract class TimelapseState {
  const TimelapseState();
}

class UninitializedState extends TimelapseState {
  const UninitializedState();
}

class FailedState extends TimelapseState {
  final Object? error;
  final StackTrace? stackTrace;

  FailedState({
    this.error,
    this.stackTrace,
  });
}

abstract class InitializedState extends TimelapseState {
  final Record record;

  const InitializedState({required this.record});
}

class DownloadingState extends InitializedState {
  final double progress;

  const DownloadingState({
    required this.progress,
    required super.record,
  });
}

class RenderingState extends InitializedState {
  final double progress;

  /// JPEG bytes of the most recently produced frame, shown live while rendering.
  final Uint8List? frame;

  /// Temporal position of [frame] within the full [totalFrames]-frame sequence.
  ///
  /// Frames are produced out of order, so this lets the UI illustrate where in
  /// the final sequence the previewed frame belongs.
  final int? frameIndex;

  /// Total number of frames in the sequence being rendered.
  final int? totalFrames;

  const RenderingState({
    required this.progress,
    required super.record,
    this.frame,
    this.frameIndex,
    this.totalFrames,
  });
}

class FinishedState extends InitializedState {
  final Uint8List data;
  final Uint8List? previewFrame;

  const FinishedState({
    required super.record,
    required this.data,
    this.previewFrame,
  });
}
