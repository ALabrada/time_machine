import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_litert/native.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Monolithic FILM inference via [IsolateInterpreter].
///
/// The single dynamic-dimensions TFLite model (input x0/x1/time, output
/// interpolated image) runs on a background isolate using the XNNPACK CPU
/// delegate. Input tensors are resized once (in [TimelapseService.load]) to the
/// requested frame size; all frames of one render share the same resolution.

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

  final IsolateInterpreter _isolateInterpreter;
  final int _width;
  final int _height;

  TimelapseService._(
    this._isolateInterpreter,
    this._width,
    this._height,
  );

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

  /// Loads the model, resizes its inputs to [width]×[height], and creates an
  /// [IsolateInterpreter] for background runs. [width]/[height] must be
  /// multiples of 32 (FILM's pyramid constraint).
  ///
  /// [onReceiveProgress] reports (received, total) bytes while the model is
  /// being downloaded and [cancelToken] can cancel that download.
  static Future<TimelapseService> load({
    required int width,
    required int height,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final (options, _) = InterpreterFactory.create(
      const PerformanceConfig.xnnpack(numThreads: 4),
    );
    final modelFile = await _downloadIfNeeded(
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
    final interpreter = Interpreter.fromFile(modelFile, options: options);

    // Fix the input resolution once up front. The IsolateInterpreter shares
    // this native interpreter, so the resize persists for every run.
    final inputShape = [1, height, width, 3];
    interpreter.resizeInputTensor(1, inputShape); // x0
    interpreter.resizeInputTensor(2, inputShape); // x1
    interpreter.allocateTensors();

    final isolateInterpreter = await IsolateInterpreter.create(
      address: interpreter.address,
    );
    return TimelapseService._(isolateInterpreter, width, height);
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

  void dispose() {
    unawaited(_isolateInterpreter.close());
  }

  /// Generates a single interpolated JPEG image at t=0.5 (the midpoint of
  /// [depth] levels of bisection; default 1 → the exact t=0.5 midpoint).
  Future<Uint8List> generateImage({
    required img.Image firstImage,
    required img.Image secondImage,
    int depth = 1,
  }) async {
    final frames = await _renderStreaming(
      _resize(firstImage, _width, _height),
      _resize(secondImage, _width, _height),
      depth,
      _width,
      _height,
      null,
    );
    return img.JpegEncoder().encode(frames[frames.length ~/ 2]);
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

    final frames = await _renderStreaming(
      _resize(firstImage, _width, _height),
      _resize(secondImage, _width, _height),
      depth,
      _width,
      _height,
      onFrame,
    );

    return _encodeGifFromImages(frames, fps);
  }

  /// Runs one interpolation step at t=0.5 via [IsolateInterpreter]. Input and
  /// output tensors were resized once in [load], so they always match
  /// [width]×[height].
  Future<Float32List> _generateFrame(
    img.Image firstImage,
    img.Image secondImage,
    int width,
    int height,
  ) async {
    // Build raw byte inputs matching the allocated tensor sizes.
    final firstBytes = _createInputBytes(_resize(firstImage, width, height));
    final secondBytes = _createInputBytes(_resize(secondImage, width, height));
    final timeBytes = Float32List.fromList([0.5]).buffer.asUint8List();

    // Model signature is [time, x0, x1]; interpolate at the fixed midpoint.
    final inputs = [timeBytes, firstBytes, secondBytes];

    // Output is always [1, height, width, 3] float32 (4 bytes per element).
    final outputBytes = Uint8List(1 * height * width * 3 * 4);
    final outputs = <int, Object>{0: outputBytes};

    await _isolateInterpreter.runForMultipleInputs(inputs, outputs);

    // Interpret the output bytes as float32.
    return Float32List.view(outputBytes.buffer);
  }

  /// Builds the full ordered frame list between [a] and [b] via recursive
  /// bisection at t=0.5, using [depth] subdivision levels, producing
  /// 2^depth+1 frames.
  ///
  /// Each midpoint is computed and reported through [onFrame] the moment it is
  /// ready (in *pre-order*, not playback order), together with its temporal
  /// index in the final sequence, so the first frame appears after a single
  /// model call for near-instant onscreen preview.
  Future<List<img.Image>> _renderStreaming(
    img.Image a,
    img.Image b,
    int depth,
    int width,
    int height,
    FrameCallback? onFrame,
  ) async {
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
        await _generateFrame(lo, hi, width, height),
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

    final frames = await render(a, b, 0, depth);
    if (onFrame != null) {
      onFrame(
        img.JpegEncoder().encode(b),
        total - 1,
        total,
        total,
        total,
      );
    }
    return frames;
  }

  // --- helpers -----------------------------------------------------------------

  /// Encodes an [img.Image] to flat float32 bytes in [0, 1] (RGB planar).
  static Uint8List _createInputBytes(img.Image image) {
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

  static img.Image _decodeImage(Float32List data, int width, int height) {
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

  static Uint8List? _encodeGifFromImages(List<img.Image> images, double fps) {
    final encoder = img.GifEncoder();
    for (var image in images) {
      encoder.addFrame(image, duration: (1000 / fps).toInt());
    }
    final gifBytes = encoder.finish();
    if (gifBytes == null) return null;
    return Uint8List.fromList(gifBytes);
  }

  static img.Image _resize(img.Image image, int width, int height) {
    if (image.width == width && image.height == height) return image;
    return img.copyResize(image,
        width: width, height: height, maintainAspect: false);
  }
}
