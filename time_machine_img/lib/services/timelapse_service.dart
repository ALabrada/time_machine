import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:time_machine_config/time_machine_config.dart';

import '_litert_platform.dart'
    show openInterpreter, TimelapseInterpreter;

/// Monolithic FILM frame interpolation shared by every platform.
///
/// The whole pipeline (model load, inference, image resize/tensor marshalling,
/// output decoding, JPEG/GIF encoding) uses only the interpreter members
/// common to the native and web surfaces — the platform-specific interpreter
/// bootstrap itself (fromFile + XNNPACK + resize on native, TF.js GraphModel
/// from a hosted model.json on web) is isolated in `_litert_platform.dart`.
///
/// * **Native**: the >100MB model is downloaded once to the app's cache file;
///   every render runs inside a single [Isolate.run] computation (TFLite
///   interpreter, XNNPACK delegate and all image work stay off the UI isolate)
///   and streams per-frame JPEG previews back over a [SendPort].
/// * **Web**: the tflite-js WASM runtime cannot run the FILM graph (its
///   XNNPACK delegate fails to prepare it, dynamic or static), so the web
///   backend loads the graph as a TF.js `GraphModel` from a hosted model.json
///   + weight shards; the "model" is a URL, not a byte blob. With no isolates,
///   the job runs inline on the UI isolate and reports frames directly through
///   [FrameCallback], while the recursive bisection yields to the event loop
///   between midpoints. Web interpreters cannot be resized, so the render
///   resolution is the model's own declared input shape rather than the
///   caller-supplied target.

/// Callback reported as each interpolated frame is produced during streaming.
///
/// [bytes] is the JPEG-encoded frame buffer, [frameIndex] its temporal position
/// within the full [totalFrames] frame sequence, and [stepsDone]/[totalSteps]
/// the rendering progress. Frames are reported the moment they are ready, in
/// pre-order bisection rather than playback order.
typedef FrameCallback = void Function(
  Uint8List bytes,
  int frameIndex,
  int totalFrames,
  int stepsDone,
  int totalSteps,
);

class TimelapseService {
  /// Native: the TFLite model is a single binary downloaded to the cache.
  static const _modelUrl =
      'https://github.com/ALabrada/frame-interpolation-tflite/raw/refs/heads/dynamic/film_net_fixed/dynamic_fp16.tflite';

  /// Web: the tflite-js WASM runtime cannot run FILM, so the web platform
  /// loads the same graph as a TF.js GraphModel hosted next to the native
  /// model (model.json + fp16 weight shards, fetched relative to it). Uses the
  /// direct `raw.githubusercontent.com` origin — the `github.com/.../raw/`
  /// alias adds a redirect hop per request, which some browsers gate on CORS.
  static const _webModelUrl =
      'https://raw.githubusercontent.com/ALabrada/frame-interpolation-tflite/dynamic/film_net_fixed/tfjs_film_web/model.json';

  final int _width;
  final int _height;
  final String? _modelPath; // native: cached model file; web: GraphModel URL

  TimelapseService._(
    this._width,
    this._height,
    this._modelPath,
  );

  /// Acquires the model location for the current platform.
  ///
  /// Native: the downloaded cache file path (reusing an existing local copy
  /// across calls). Web: the TF.js GraphModel URL; the browser HTTP cache is
  /// pre-warmed here so the graph loader's own fetches are cache hits, but the
  /// loader then fetches the artifacts itself.
  ///
  /// [onReceiveProgress] reports (received, total) bytes while downloading and
  /// [cancelToken] can cancel an in-flight download; both are ignored when the
  /// model is already cached on native.
  static Future<String?> _acquireModel({
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (kIsWeb) {
      // The web model is a TF.js GraphModel split into model.json + weight
      // shards; the graph loader fetches each artifact itself. Pre-warm the
      // browser HTTP cache (and report honest progress) by fetching the
      // artifacts here first, so the loader's own fetches are served almost
      // entirely from cache. FILM's graph is dynamic, so there is nothing to
      // choose on the host side — the shards are always the whole model.
      //
      // Best-effort: if a fetch fails here (model not published yet, CORS,
      // transient network), the TF.js loader runs regardless and is the single
      // source of truth for availability — it ends the job with its own,
      // clearer error instead of a bare Dio connection error.
      try {
        final modelJson = await Dio().get<Uint8List>(
          _webModelUrl,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (onReceiveProgress == null || total <= 0) return;
            onReceiveProgress(received, total);
          },
        );
        final shardNames = _webModelShardNames(modelJson.data!);
        // model.json counts toward the reported total so the bar reflects the
        // full artifact set, not just the shards.
        var accumulated = modelJson.data!.lengthInBytes;
        for (final name in shardNames) {
          var shardTotal = 0;
          await Dio().get<Uint8List>(
            _resolveWebModelUrl(name),
            options: Options(responseType: ResponseType.bytes),
            cancelToken: cancelToken,
            // Progress relative to (everything fetched so far + this shard),
            // which converges to 100% as the fetch drains.
            onReceiveProgress: (received, total) {
              shardTotal = total;
              if (onReceiveProgress == null || total <= 0) return;
              onReceiveProgress(accumulated + received, accumulated + total);
            },
          );
          if (shardTotal > 0) accumulated += shardTotal;
        }
      } catch (error) {
        debugPrint('Web model pre-warm failed; TF.js loader will retry: '
            '$error');
      }
      return _webModelUrl;
    }

    final cacheDir = await getApplicationSupportDirectory();
    final file = File('${cacheDir.path}/film.tflite');
    try {
      if (!await file.exists()) {
        await Dio().download(
          _modelUrl,
          file.path,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        );
      }
      return file.path;
    } catch (_) {
      await file.delete();
      rethrow;
    }
  }

  /// Names of the weight shard files referenced by a GraphModel model.json
  /// (e.g. `group1-shard1of15.bin`).
  static List<String> _webModelShardNames(Uint8List modelJson) {
    final decoded = jsonDecode(utf8.decode(modelJson)) as Map<String, dynamic>;
    final manifest =
        decoded['weightsManifest'] as List<dynamic>? ?? const [];
    if (manifest.isEmpty) return const [];
    final paths = (manifest.first as Map<String, dynamic>)['paths'];
    if (paths is! List<dynamic>) return const [];
    return [for (final path in paths) path as String];
  }

  /// Resolves a weight shard name against the hosted model.json URL, e.g.
  /// `.../tfjs_film_web/model.json` + `group1-shard1of15.bin` ->
  /// `.../tfjs_film_web/group1-shard1of15.bin`.
  static String _resolveWebModelUrl(String shardName) =>
      Uri.parse(_webModelUrl).resolve(shardName).toString();

  /// Loads the model (downloading it first if needed). It is *not* opened
  /// here: the interpreter is created inside each render job, so no native
  /// handle ever lives on the main isolate.
  ///
  /// [width]/[height] must be multiples of 32 (FILM's pyramid constraint). On
  /// the web they are only a fallback: the render resolution is the model's own
  /// declared input shape (see [TimelapseInterpreter.resolveRenderSize]).
  ///
  /// [onReceiveProgress] reports (received, total) bytes while the model is
  /// being downloaded and [cancelToken] can cancel that download.
  static Future<TimelapseService> load({
    required int width,
    required int height,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final modelPath = await _acquireModel(
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
    return TimelapseService._(
      width,
      height,
      modelPath,
    );
  }

  /// Computes a target (width, height) preserving the aspect ratio of
  /// [image] with the longer side capped at [maxDimension] (default 512),
  /// each dimension rounded **down** to a multiple of 32. Call this before
  /// the service is created and pass the result to [load].
  static (int, int) computeTargetSize(
    img.Image image, {
    int maxDimension = 512,
  }) {
    final aspect = image.width / image.height;
    int w, h;
    if (aspect >= 1.0) {
      w = maxDimension;
      h = (maxDimension / aspect).round();
    } else {
      h = maxDimension;
      w = (maxDimension * aspect).round();
    }
    w = (w ~/ 32) * 32;
    h = (h ~/ 32) * 32;
    if (w < 32) w = 32;
    if (h < 32) h = 32;
    return (w, h);
  }

  /// Nothing native lives on the main isolate (native) or between renders
  /// (web), so disposing is a no-op.
  void dispose() {}

  /// Generates a single interpolated JPEG image at t=0.5 (the midpoint of
  /// [depth] levels of bisection; default 1 → the exact t=0.5 midpoint).
  Future<Uint8List> generateImage({
    required img.Image firstImage,
    required img.Image secondImage,
    int depth = 1,
  }) async {
    final bytes = await _render(
      firstImage: firstImage,
      secondImage: secondImage,
      depth: depth,
      fps: 1,
      encodeGif: false,
      onFrame: null,
    );
    if (bytes == null) {
      throw StateError('Rendering produced no output image.');
    }
    return bytes;
  }

  /// Generates a GIF interpolating from [firstImage] to [secondImage].
  ///
  /// The timeline is split by recursive bisection at t=0.5 — the only way FILM
  /// yields accurate full-range frames. Depth `d` produces 2^d intervals and
  /// 2^d + 1 frames INCLUDING both source frames (X + 1 with X = 2^d even),
  /// all exactly equidistant in time. Depth is chosen so 2^depth == frames
  /// needed for [duration] at [fps]; the app only exposes the combination that
  /// satisfies it exactly (2s at 4/8/16 fps → 2^depth = 2 * fps). Each frame is
  /// reported through [onFrame] the moment it is ready (out of playback order),
  /// so the first frame appears almost immediately for onscreen preview.
  /// When omitted, [fps] defaults to [ConfigurationService.defaultFps].
  Future<Uint8List?> generateVideo({
    required img.Image firstImage,
    required img.Image secondImage,
    Duration duration = const Duration(seconds: 2),
    double? fps,
    FrameCallback? onFrame,
  }) async {
    final effectiveFps =
        fps ?? ConfigurationService.defaultFps.toDouble();
    // frames to show at `fps` over `duration` = intervals to subdivide =
    // smallest power of two X = 2^depth such that 2^depth >= duration*fps.
    final neededFrames = (duration.inMilliseconds * effectiveFps / 1000).ceil();
    var depth = 0;
    while ((1 << depth) < neededFrames) {
      depth++;
    }

    return _render(
      firstImage: firstImage,
      secondImage: secondImage,
      depth: depth,
      fps: effectiveFps,
      onFrame: onFrame,
      encodeGif: true,
    );
  }

  /// Runs one render.
  ///
  /// Native: dispatches it to a background isolate via [Isolate.run]; the only
  /// channel back is [progressPort], which carries the per-frame JPEG previews
  /// that [onFrame] forwards to the UI. Web: there are no isolates, so the job
  /// runs inline on the UI isolate and reports frames directly through
  /// [onFrame].
  Future<Uint8List?> _render({
    required img.Image firstImage,
    required img.Image secondImage,
    required int depth,
    required double fps,
    FrameCallback? onFrame,
    required bool encodeGif,
  }) async {
    if (kIsWeb) {
      final output = await _renderJob(
        modelPath: _modelPath,
        firstImage: firstImage,
        secondImage: secondImage,
        width: _width,
        height: _height,
        depth: depth,
        fps: fps,
        encodeGif: encodeGif,
        onFrame: onFrame,
      );
      return encodeGif ? output.gifBytes : output.midpointBytes;
    }

    final progressPort = ReceivePort();
    final progressSubscription = progressPort.listen((message) {
      if (message is _FrameProgress) {
        onFrame?.call(
          message.bytes,
          message.frameIndex,
          message.totalFrames,
          message.stepsDone,
          message.totalSteps,
        );
      }
    });

    // Arguments below are evaluated here, on the main isolate, and handed to
    // [_runRenderJob] as plain values; nothing that lives in this activation's
    // scope (e.g. [onFrame], captured by the listen closure above) can leak
    // into the background isolate.
    try {
      final output = await _runRenderJob(
        modelPath: _modelPath,
        firstImage: firstImage,
        secondImage: secondImage,
        width: _width,
        height: _height,
        depth: depth,
        fps: fps,
        encodeGif: encodeGif,
        progressPort: progressPort.sendPort,
      );
      return encodeGif ? output.gifBytes : output.midpointBytes;
    } finally {
      await progressSubscription.cancel();
      progressPort.close();
    }
  }
}

/// Dispatches [_renderJob] via [Isolate.run] (native).
///
/// Top-level on purpose: the closure it hands to [Isolate.run] is created here,
/// where the only in-scope cells are these sendable parameters. Written inside
/// [_TimelapseService._render] instead, the closure would share context cells
/// with the sibling listen closure that captures [onFrame] (and through it the
/// controller), making the whole message unsendable.
Future<_RenderOutput> _runRenderJob({
  required String? modelPath,
  required img.Image firstImage,
  required img.Image secondImage,
  required int width,
  required int height,
  required int depth,
  required double fps,
  required bool encodeGif,
  required SendPort progressPort,
}) {
  return Isolate.run(
    () => _renderJob(
      modelPath: modelPath,
      firstImage: firstImage,
      secondImage: secondImage,
      width: width,
      height: height,
      depth: depth,
      fps: fps,
      encodeGif: encodeGif,
      onFrame: null,
      progressPort: progressPort,
    ),
  );
}

/// Renders the full interpolated sequence.
///
/// Entry point of the native one-shot background isolate; on the web it runs
/// inline on the UI isolate ([_TimelapseService._render]) with [onFrame]
/// populated instead of [progressPort]. Builds its own interpreter from the
  /// platform's model source, fixes the render resolution once via
  /// [TimelapseInterpreter.resolveRenderSize], and streams a JPEG preview of
  /// each frame back through [progressPort]/[onFrame] as it is produced.
Future<_RenderOutput> _renderJob({
  required String? modelPath,
  required img.Image firstImage,
  required img.Image secondImage,
  required int width,
  required int height,
  required int depth,
  required double fps,
  required bool encodeGif,
  FrameCallback? onFrame,
  SendPort? progressPort,
}) async {
  final interpreter = await openInterpreter(modelPath: modelPath);
  try {
    final (renderWidth, renderHeight) =
        interpreter.resolveRenderSize(width, height);

    Uint8List? midpointJpeg;
    final frames = await _renderStreaming(
      interpreter,
      firstImage,
      secondImage,
      depth,
      renderWidth,
      renderHeight,
      (bytes, frameIndex, totalFrames, stepsDone, totalSteps) {
        // The first midpoint produced by pre-order bisection is exactly the
        // temporal middle of the sequence (t=0.5), so it doubles as the
        // "single interpolated image" output of generateImage.
        midpointJpeg ??= bytes;
        progressPort?.send(_FrameProgress(
          bytes: bytes,
          frameIndex: frameIndex,
          totalFrames: totalFrames,
          stepsDone: stepsDone,
          totalSteps: totalSteps,
        ));
        onFrame?.call(
          bytes,
          frameIndex,
          totalFrames,
          stepsDone,
          totalSteps,
        );
      },
    );

    if (!encodeGif) {
      return _RenderOutput(midpointBytes: midpointJpeg);
    }
    return _RenderOutput(gifBytes: _encodeGifFromImages(frames, fps));
  } finally {
    interpreter.close();
  }
}

/// Runs one interpolation step at t=0.5 via the platform
  /// [TimelapseInterpreter]. Output is always [1, height, width, 3] float32
  /// (4 bytes per element).
  Future<Float32List> _generateFrame(
    TimelapseInterpreter interpreter,
    img.Image firstImage,
    img.Image secondImage,
    int width,
    int height,
  ) async {
    // Build raw byte inputs matching the interpreter's tensor shapes.
    final firstBytes = _createInputBytes(_resize(firstImage, width, height));
    final secondBytes = _createInputBytes(_resize(secondImage, width, height));
    final timeBytes = _timeInputBytes(interpreter);

    // Model signature is [time, x0, x1]; interpolate at the fixed midpoint.
    final inputs = <Object>[timeBytes, firstBytes, secondBytes];
    // The output is exactly the resolution the interpreter was configured to
    // (resolveRenderSize) — [1, height, width, 3] float32. Sizing the buffer
    // from the interpreter's *reported* output shape is wrong on native, where
    // the dynamic FILM graph reports an unusable placeholder shape until the
    // first run.
    final outputBytes = Uint8List(1 * height * width * 3 * 4);

    await interpreter.runForMultipleInputs(inputs, <int, Object>{0: outputBytes});
    return Float32List.view(outputBytes.buffer);
  }

  /// Builds the `time` input scaled to the model's declared time-tensor shape,
  /// all elements at t=0.5 (the midpoint). Guards against unusable shapes.
  Uint8List _timeInputBytes(TimelapseInterpreter interpreter) {
  var count = 1;
  final inputs = interpreter.getInputTensors();
  if (inputs.isNotEmpty) {
    var n = 1;
    for (final dim in inputs[0].shape) {
      if (dim <= 0) {
        n = 1;
        break;
      }
      n *= dim;
    }
    count = n;
  }
  final values = Float32List(count);
  for (var i = 0; i < values.length; i++) {
    values[i] = 0.5;
  }
  return values.buffer.asUint8List();
}

/// Builds the full ordered frame list between [a] and [b] via recursive
/// bisection at t=0.5, using [depth] subdivision levels, producing
/// 2^depth+1 frames.
///
/// Each midpoint is computed and reported through [onFrame] the moment it is
/// ready (in *pre-order*, not playback order), together with its temporal
/// index in the final sequence.
Future<List<img.Image>> _renderStreaming(
  TimelapseInterpreter interpreter,
  img.Image a,
  img.Image b,
  int depth,
  int width,
  int height,
  FrameCallback? onFrame,
) async {
  // Both endpoints are resized to the model resolution once; every
  // intermediate comes out of the model at that size already.
  final ra = _resize(a, width, height);
  final rb = _resize(b, width, height);

  var done = 1; // both endpoints count as shown immediately
  final total = (1 << depth) + 1;

  Future<List<img.Image>> render(
    img.Image lo,
    img.Image hi,
    int base,
    int d,
  ) async {
    if (d <= 0) return [lo, hi];
    final mid = _decodeImage(
      await _generateFrame(interpreter, lo, hi, width, height),
      width,
      height,
    );
    final midIndex = base + (1 << (d - 1));
    done += 1;
    onFrame?.call(
      img.JpegEncoder().encode(mid),
      midIndex,
      total,
      done,
      total,
    );
    // On the web there are no isolates, so this yield lets the browser flush
    // the frame we just published through [onFrame]; a harmless microtask on
    // native.
    await Future<void>.delayed(Duration.zero);
    final left = await render(lo, mid, base, d - 1);
    final right = await render(mid, hi, midIndex, d - 1);
    return [...left, ...right.skip(1)];
  }

  final frames = await render(ra, rb, 0, depth);
  if (onFrame != null) {
    onFrame(
      img.JpegEncoder().encode(rb),
      total - 1,
      total,
      total,
      total,
    );
  }
  return frames;
}

// --- image helpers -----------------------------------------------------------

/// Encodes an [img.Image] to flat float32 bytes in [0, 1] (RGB planar).
Uint8List _createInputBytes(img.Image image) {
  final data = Float32List(image.width * image.height * 3);
  int idx = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      data[idx++] = pixel.r / 255.0;
      data[idx++] = pixel.g / 255.0;
      data[idx++] = pixel.b / 255.0;
    }
  }
  return data.buffer.asUint8List();
}

/// Reconstructs an [img.Image] from the model's float32 output tensor.
img.Image _decodeImage(Float32List data, int width, int height) {
  final outputImage = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = (y * width + x) * 3;
      final r = (data[idx] * 255.0).clamp(0, 255).toInt();
      final g = (data[idx + 1] * 255.0).clamp(0, 255).toInt();
      final b = (data[idx + 2] * 255.0).clamp(0, 255).toInt();
      outputImage.setPixelRgb(x, y, r, g, b);
    }
  }
  return outputImage;
}

Uint8List? _encodeGifFromImages(List<img.Image> images, double fps) {
  final encoder = img.GifEncoder();
  for (var image in images) {
    encoder.addFrame(image, duration: (100 / fps).toInt());
  }
  final gifBytes = encoder.finish();
  if (gifBytes == null) return null;
  return Uint8List.fromList(gifBytes);
}

img.Image _resize(img.Image image, int width, int height) {
  if (image.width == width && image.height == height) return image;
  return img.copyResize(image,
      width: width, height: height, maintainAspect: false);
}

// --- job protocol messages (sent across the isolate boundary) ----------------

/// A per-frame preview emitted by the render job while it runs. Only sendable
/// data crosses the boundary.
class _FrameProgress {
  _FrameProgress({
    required this.bytes,
    required this.frameIndex,
    required this.totalFrames,
    required this.stepsDone,
    required this.totalSteps,
  });

  final Uint8List bytes;
  final int frameIndex;
  final int totalFrames;
  final int stepsDone;
  final int totalSteps;
}

/// The output of a render job, delivered as the [Isolate.run] return value on
/// native and as the direct return value on web.
///
/// Errors inside the job propagate out of [Isolate.run] directly, so the
/// result never carries one.
class _RenderOutput {
  _RenderOutput({
    this.gifBytes,
    this.midpointBytes,
  });

  final Uint8List? gifBytes;
  final Uint8List? midpointBytes;
}