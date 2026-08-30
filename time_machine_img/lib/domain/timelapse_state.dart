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

  FailedState({this.error, this.stackTrace,});
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

  const RenderingState({
    required this.progress,
    required super.record,
  });
}

class FinishedState extends InitializedState {
  final Uint8List data;

  const FinishedState({required super.record, required this.data});
}