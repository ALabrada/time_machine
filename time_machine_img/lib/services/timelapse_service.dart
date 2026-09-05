import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_litert/native.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Monolithic FILM interpolation with every frame rendered off the UI isolate.
///
/// Each render runs inside a single [Isolate.run] computation: the TFLite
/// interpreter and its XNNPACK delegate are created, resized, invoked and
/// closed entirely within that background isolate, and so is all of the
/// `image`-package work (resize, tensor marshalling, output decoding, JPEG/GIF
/// encoding). The main isolate only downloads the model, dispatches the job
/// and forwards the per-frame JPEG previews it receives over a [SendPort]
/// stream, so the UI thread stays responsive for the whole render.

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
  static const _modelUrl =
      'https://github.com/ALabrada/frame-interpolation-tflite/raw/refs/heads/dynamic/film_net_fixed/dynamic_fp16.tflite';

  final int _width;
  final int _height;
  final File _modelFile;

  TimelapseService._(this._width, this._height, this._modelFile);

  /// Downloads the model to the app's cache (reusing an existing local copy)
  /// and returns its [File].
  ///
  /// [onReceiveProgress] reports (received, total) bytes while downloading and
  /// [cancelToken] can cancel an in-flight download; both are ignored when the
  /// model is already cached.
  static Future<File> _downloadIfNeeded({
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
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
      return file;
    } catch (_) {
      await file.delete();
      rethrow;
    }
  }

  /// Loads the model (downloading it first if needed). It is *not* opened
  /// here: the interpreter is created inside the per-render background isolate
  /// in [_renderJob], so no native handle ever lives on the main isolate.
  ///
  /// [width]/[height] must be multiples of 32 (FILM's pyramid constraint).
  ///
  /// [onReceiveProgress] reports (received, total) bytes while the model is
  /// being downloaded and [cancelToken] can cancel that download.
  static Future<TimelapseService> load({
    required int width,
    required int height,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final modelFile = await _downloadIfNeeded(
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
    return TimelapseService._(width, height, modelFile);
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

  /// Nothing native lives on this isolate — the interpreter is created and
  /// closed inside each [Isolate.run] job — so disposing is a no-op.
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
    );
    if (bytes == null) {
      throw StateError('Rendering produced no output image.');
    }
    return bytes;
  }

  /// Generates a GIF interpolating from [firstImage] to [secondImage].
  ///
  /// Frames are produced by recursive bisection at t=0.5 — the only way FILM
  /// yields accurate full-range frames. Each intermediate is computed and
  /// reported through [onFrame] the moment it is ready (out of playback order),
  /// so the first frame appears almost immediately for onscreen preview. Depth
  /// is chosen so 2^depth + 1 >= frames needed for [duration] at [fps].
  Future<Uint8List?> generateVideo({
    required img.Image firstImage,
    required img.Image secondImage,
    Duration duration = const Duration(seconds: 5),
    double fps = 24,
    FrameCallback? onFrame,
  }) async {
    final neededFrames = (duration.inMilliseconds * fps / 1000).ceil();
    var depth = 0;
    while ((1 << depth) < neededFrames) {
      depth++;
    }

    return _render(
      firstImage: firstImage,
      secondImage: secondImage,
      depth: depth,
      fps: fps,
      onFrame: onFrame,
      encodeGif: true,
    );
  }

  /// Runs one render in a background isolate via [Isolate.run].
  ///
  /// The entire computation — model load, inference, and every image
  /// creation/transformation — happens off the main isolate in [_renderJob].
  /// The only channel back is [progressPort], which carries the per-frame JPEG
  /// previews that [onFrame] forwards to the UI.
  Future<Uint8List?> _render({
    required img.Image firstImage,
    required img.Image secondImage,
    required int depth,
    required double fps,
    FrameCallback? onFrame,
    required bool encodeGif,
  }) async {
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
        modelPath: _modelFile.path,
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

/// Dispatches [_renderJob] via [Isolate.run].
///
/// Top-level on purpose: the closure it hands to [Isolate.run] is created here,
/// where the only in-scope cells are these sendable parameters. Written inside
/// [_TimelapseService._render] instead, the closure would share context cells
/// with the sibling listen closure that captures [onFrame] (and through it the
/// controller), making the whole message unsendable.
Future<_RenderOutput> _runRenderJob({
  required String modelPath,
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
      progressPort: progressPort,
    ),
  );
}

// --- render job (runs on a one-shot background isolate) ----------------------

/// Entry point executed by [Isolate.run]: creates its own interpreter from
/// [modelPath], renders the full interpolated sequence, and streams a JPEG
/// preview of each frame back to [progressPort] as it is produced.
Future<_RenderOutput> _renderJob({
  required String modelPath,
  required img.Image firstImage,
  required img.Image secondImage,
  required int width,
  required int height,
  required int depth,
  required double fps,
  required bool encodeGif,
  required SendPort progressPort,
}) async {
  // The interpreter and its XNNPACK delegate live only in this isolate; they
  // are closed in the finally block when the job completes (or errors).
  final (options, _) = InterpreterFactory.create(
    const PerformanceConfig.xnnpack(numThreads: 4),
  );
  final interpreter = Interpreter.fromFile(File(modelPath), options: options);
  try {
    // Fix the input resolution once up front; every frame shares it. The
    // output tensor then always matches [1, height, width, 3] float32.
    final inputShape = [1, height, width, 3];
    interpreter.resizeInputTensor(1, inputShape); // x0
    interpreter.resizeInputTensor(2, inputShape); // x1
    interpreter.allocateTensors();

    Uint8List? midpointJpeg;
    final frames = await _renderStreaming(
      interpreter,
      firstImage,
      secondImage,
      depth,
      width,
      height,
      (bytes, frameIndex, totalFrames, stepsDone, totalSteps) {
        // The first midpoint produced by pre-order bisection is exactly the
        // temporal middle of the sequence (t=0.5), so it doubles as the
        // "single interpolated image" output of generateImage.
        midpointJpeg ??= bytes;
        progressPort.send(_FrameProgress(
          bytes: bytes,
          frameIndex: frameIndex,
          totalFrames: totalFrames,
          stepsDone: stepsDone,
          totalSteps: totalSteps,
        ));
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

/// Runs one interpolation step at t=0.5 via the in-isolate [Interpreter].
/// Output is always [1, height, width, 3] float32 (4 bytes per element).
Float32List _generateFrame(
  Interpreter interpreter,
  img.Image firstImage,
  img.Image secondImage,
  int width,
  int height,
) {
  // Build raw byte inputs matching the allocated tensor sizes.
  final firstBytes = _createInputBytes(_resize(firstImage, width, height));
  final secondBytes = _createInputBytes(_resize(secondImage, width, height));
  final timeBytes = Float32List.fromList([0.5]).buffer.asUint8List();

  // Model signature is [time, x0, x1]; interpolate at the fixed midpoint.
  final inputs = <Object>[timeBytes, firstBytes, secondBytes];
  final outputBytes = Uint8List(1 * height * width * 3 * 4);

  interpreter.runForMultipleInputs(inputs, <int, Object>{0: outputBytes});
  return Float32List.view(outputBytes.buffer);
}

/// Builds the full ordered frame list between [a] and [b] via recursive
/// bisection at t=0.5, using [depth] subdivision levels, producing
/// 2^depth+1 frames.
///
/// Each midpoint is computed and reported through [onFrame] the moment it is
/// ready (in *pre-order*, not playback order), together with its temporal
/// index in the final sequence.
Future<List<img.Image>> _renderStreaming(
  Interpreter interpreter,
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
      _generateFrame(interpreter, lo, hi, width, height),
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

// --- image helpers (always run inside the render job isolate) ----------------

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
    encoder.addFrame(image, duration: (1000 / fps).toInt());
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

/// The output of a render job, delivered as the [Isolate.run] return value.
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