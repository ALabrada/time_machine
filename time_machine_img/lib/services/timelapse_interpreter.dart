/// A single model tensor's declared shape.
///
/// Dimensions can be dynamic (web TF.js graphs report `null` for unknown dims,
/// TFLite reports `-1`); both are normalized to `-1` here so callers can guard
/// with `dim <= 0`.
class TimelapseTensor {
  TimelapseTensor(this.shape);

  /// Dimensions in order. Dynamic markers are `-1`.
  final List<int> shape;
}

/// The interpreter surface the timelapse pipeline actually uses, shared by the
/// native TFLite (LiteRT) backend and the web TF.js GraphModel backend.
///
/// Native and web interpreters in flutter_litert cannot be imported together,
/// and the web tflite-js WASM runtime cannot handle the FILM graph at all (its
/// XNNPACK delegate fails to prepare), so the web path runs the same graph as
/// a TF.js GraphModel instead. Both backends marshal raw float32 bytes the
/// same way (`runForMultipleInputs` schedules work and writes results into the
/// caller-provided output buffers), which is what keeps [TimelapseService]
/// platform-agnostic.
abstract class TimelapseInterpreter {
  /// Declared shapes of the input tensors (positional: time, x0, x1).
  List<TimelapseTensor> getInputTensors();

  /// Runs one interpolation at t=0.5.
  ///
  /// [inputs] is a positional list of raw float32 byte buffers
  /// ([time, x0, x1]); [outputs] maps tensor index -> pre-allocated byte
  /// buffer that the output is written into. Completes once the output buffer
  /// holds the model result.
  Future<void> runForMultipleInputs(List<Object> inputs, Map<int, Object> outputs);

  /// Fixes the render resolution.
  ///
  /// Native interpreters are resized to [targetWidth] x [targetHeight] and
  /// return them as-is. Web interpreters cannot be resized; they return the
  /// model's *declared* input shape, falling back to the target when the
  /// declared shape is unusable (dynamic -1 markers or a wrong rank).
  (int, int) resolveRenderSize(int targetWidth, int targetHeight);

  /// Releases the underlying backend resources.
  void close();
}