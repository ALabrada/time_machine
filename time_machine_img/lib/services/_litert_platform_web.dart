import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'timelapse_interpreter.dart';

/// Web backend for the timelapse pipeline, running FILM as a TF.js
/// [GraphModel](https://js.tensorflow.org/api/latest/#loadGraphModel) instead
/// of through flutter_litert's tflite-js WASM runtime.
///
/// flutter_litert cannot run FILM on the web: every web build (dynamic or
/// static, fp32 or fp16) fails inside the runtime's XNNPACK CPU delegate
/// (tflite-js `Aborted()`, or LiteRT.js `XNNPack delegate failed to reshape
/// runtime` -> zero output), while control models run fine — the failure is
/// specific to the FILM graph, not the runtime or the fp16/Vulkan pipeline.
///
/// The web implementation of litert is therefore not a replacement for the
/// injected TF.js bundle: its tflite-js WASM interpreter is fixed-shape with
/// no resize API, and both of its runtimes are XNNPACK delegates that fail to
/// prepare this graph. (They would also inject the *same* tfjs-family scripts
/// from the same CDN — `tf-core`, `tf-backend-cpu`, `tf-tflite` — so moving
/// back to them would not remove the third-party dependency.) Hence the one
/// script this page ever injects is the pinned TF.js bundle below, loaded
/// lazily, to run the same graph converted to a TF.js GraphModel (model.json
/// + fp16-quantized weight shards, hosted next to the native model).
///
/// The marshalling contract is identical to the native backend: inputs are
/// positional raw float32 byte buffers ([time, x0, x1]), the output is written
/// float32 into a [1, height, width, 3] Python layout — only the execution
/// engine differs, so [TimelapseService] stays platform-agnostic.

/// The TF.js bundle is fetched lazily (and only once) from the same CDN
/// flutter_litert already used for its runtime scripts, pinned to the version
/// the model conversion was validated against. It is never loaded unless a web
/// timelapse render actually runs.
const _tfJsUrl =
    'https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0/dist/tf.min.js';

Future<TimelapseInterpreter> openInterpreter({
  String? modelPath,
}) async {
  // On the web [modelPath] carries the GraphModel's model.json URL; the
  // browser fetches the weight shards relative to it.
  final modelUrl = modelPath!;
  await _ensureTfJs();
  return _GraphInterpreter(
    _GraphModel(await _loadGraphModel(modelUrl)),
  );
}

/// Returns the loaded GraphModel handle, retrying once on the CPU backend.
///
/// Wraps the final failure with the model URL and the underlying JS error so
/// the user sees why the model could not load (it may not have been published,
/// or CORS may block the fetch) instead of a bare XHR "connection error".
Future<JSObject> _loadGraphModel(String modelUrl) async {
  Object? firstError;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      if (attempt == 1) {
        // The default WebGL backend occasionally fails to initialize on some
        // drivers; the graph uses only standard kernels, so CPU always works.
        await _tf.setBackend('cpu').toDart;
      }
      return await _tf.loadGraphModel(modelUrl).toDart;
    } catch (error) {
      firstError ??= error;
    }
  }
  throw StateError(
    'Could not load the film model from $modelUrl. '
    'Check that it has been published and reachable from the browser. '
    '($firstError)',
  );
}

// --- TF.js JS interop declarations ------------------------------------------

extension type _Tf(JSObject _) {
  external JSPromise<JSObject> loadGraphModel(String modelUrl);
  external JSObject tensor(JSFloat32Array values, JSArray<JSNumber> shape);
  external JSPromise<JSBoolean> setBackend(String name);
}

extension type _GraphModel(JSObject _) {
  external JSArray<JSAny?> get inputs;
  /// Runs the graph synchronously and returns the output tensor. This graph
  /// has no control flow or dynamic output shapes, so `execute()` is legal
  /// (and avoids the library's `executeAsync` info log recommending it).
  external JSObject execute(JSAny inputs);
  external void dispose();
}

extension type _TensorInfo(JSObject _) {
  external String get name;
  external JSArray<JSAny?> get shape;
}

extension type _Tensor(JSObject _) {
  external JSFloat32Array dataSync();
  external void dispose();
}

_Tf get _tf => _Tf(globalContext['tf'] as JSObject);

// --- TF.js toolbar loading ---------------------------------------------------

Future<void>? _tfLoading;

/// Ensures the `tf` global exists, injecting the pinned TF.js bundle on
/// first use. Idempotent and safe across interpreters.
Future<void> _ensureTfJs() {
  final pending = _tfLoading;
  if (pending != null) return pending;

  final completer = Completer<void>();
  _tfLoading = completer.future;

  try {
    if (globalContext['tf'] != null) {
      completer.complete();
      return completer.future;
    }
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = _tfJsUrl;
    script.async = true;
    script.addEventListener(
        'load', ((web.Event _) => completer.complete()).toJS);
    script.addEventListener('error', ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('Failed to load TF.js from $_tfJsUrl.'));
      }
    }).toJS);
    web.document.head?.append(script);
  } catch (error) {
    _tfLoading = null;
    completer.completeError(error);
  }
  return completer.future;
}

// --- Interpreter -------------------------------------------------------------

/// Executes the FILM GraphModel with positional float32 byte I/O identically
/// to the native interpreter.
final class _GraphInterpreter implements TimelapseInterpreter {
  _GraphInterpreter(this._model);

  final _GraphModel _model;

  late final List<_TensorInfo> _inputInfos = _readTensorInfos(_model.inputs);

  /// The render resolution fixed by [resolveRenderSize], in
  /// (width, height); the buffers handed to [runForMultipleInputs] are sized
  /// with the same values by the caller.
  (int, int)? _renderSize;

  static List<_TensorInfo> _readTensorInfos(JSArray<JSAny?> array) {
    return [
      for (var i = 0; i < array.length; i++)
        _TensorInfo(array[i] as JSObject),
    ];
  }

  static List<int> _dimsOf(_TensorInfo info) {
    final shape = info.shape;
    return [
      for (var i = 0; i < shape.length; i++)
        shape[i] == null ? -1 : (shape[i] as JSNumber).toDartInt,
    ];
  }

  @override
  List<TimelapseTensor> getInputTensors() {
    return [for (final info in _inputInfos) TimelapseTensor(_dimsOf(info))];
  }

  @override
  (int, int) resolveRenderSize(int targetWidth, int targetHeight) {
    // Mirrors the old web behavior: use the model's *declared* input shape
    // when it is usable, else fall back to the caller-supplied target (FILM's
    // graph is dynamic, so this is the fallback in practice).
    for (final index in [1, 2]) {
      if (index >= _inputInfos.length) break;
      final dims = _dimsOf(_inputInfos[index]);
      if (dims.length != 4) continue;
      final height = dims[1];
      final width = dims[2];
      if (height > 0 && width > 0) {
        _renderSize = (width, height);
        return (width, height);
      }
    }
    _renderSize = (targetWidth, targetHeight);
    return (targetWidth, targetHeight);
  }

  @override
  Future<void> runForMultipleInputs(
    List<Object> inputs,
    Map<int, Object> outputs,
  ) async {
    final (width, height) = _renderSize!;
    final tensors = <JSObject>[
      for (final info in _inputInfos)
        switch (info.name) {
          'time' => _makeInputTensor(inputs[0] as Uint8List, [1, 1]),
          _ when info.name.startsWith('x0') =>
            _makeInputTensor(inputs[1] as Uint8List, [1, height, width, 3]),
          _ when info.name.startsWith('x1') =>
            _makeInputTensor(inputs[2] as Uint8List, [1, height, width, 3]),
          _ => throw StateError(
              'Unexpected FILM input tensor "${info.name}".'),
        },
    ];

    _Tensor? result;
    try {
      result = _Tensor(_model.execute(tensors.toJS));
      final floats = result.dataSync().toDart;
      final outputBytes = outputs[0] as Uint8List;
      outputBytes.setAll(
        0,
        Uint8List.view(floats.buffer, floats.offsetInBytes, floats.lengthInBytes),
      );
    } finally {
      for (final tensor in tensors) {
        _Tensor(tensor).dispose();
      }
      result?.dispose();
    }
  }

  static JSObject _makeInputTensor(Uint8List bytes, List<int> dims) {
    final floats = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    return _tf.tensor(floats.toJS, _jsShape(dims));
  }

  static JSArray<JSNumber> _jsShape(List<int> dims) =>
      [for (final dim in dims) dim.toJS].toJS;

  @override
  void close() {
    _model.dispose();
  }
}