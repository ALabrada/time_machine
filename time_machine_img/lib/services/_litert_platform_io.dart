import 'dart:io';

import 'package:flutter_litert/native.dart' as fln;

import 'timelapse_interpreter.dart';

/// Native: opens the model from the cached [modelPath] file with an XNNPACK
/// (4-thread) delegate.
Future<TimelapseInterpreter> openInterpreter({
  String? modelPath,
}) async {
  final (options, _) = fln.InterpreterFactory.create(
    const fln.PerformanceConfig.xnnpack(numThreads: 4),
  );
  final native = fln.Interpreter.fromFile(File(modelPath!), options: options);
  return _NativeInterpreter(native);
}

/// Thin adapter presenting the native LiteRT interpreter through the shared
/// [TimelapseInterpreter] surface.
final class _NativeInterpreter implements TimelapseInterpreter {
  _NativeInterpreter(this._native);

  final fln.Interpreter _native;

  @override
  List<TimelapseTensor> getInputTensors() => [
        for (final tensor in _native.getInputTensors()) TimelapseTensor(tensor.shape),
      ];

  @override
  Future<void> runForMultipleInputs(
    List<Object> inputs,
    Map<int, Object> outputs,
  ) async {
    _native.runForMultipleInputs(inputs, outputs);
  }

  @override
  (int, int) resolveRenderSize(int targetWidth, int targetHeight) {
    final inputShape = [1, targetHeight, targetWidth, 3];
    _native.resizeInputTensor(1, inputShape); // x0
    _native.resizeInputTensor(2, inputShape); // x1
    _native.allocateTensors();
    return (targetWidth, targetHeight);
  }

  @override
  void close() {
    _native.close();
  }
}