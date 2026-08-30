import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_tensor_preprocessing/dart_tensor_preprocessing.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_litert/native.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TimelapseService {
  static const assetName = 'assets/film.tflite';
  static const modelUrl = 'https://raw.githubusercontent.com/egemenertugrul/frame-interpolation-tflite-unity/main/FILM_TFLite_UnityProject/Assets/StreamingAssets/model_512_quant_float16.tflite';

  final IsolateInterpreter interpreter;
  final List<Tensor> outputTensors;
  bool disposed = false;

  TimelapseService({
    required this.interpreter,
    required this.outputTensors,
  });

  void dispose() {
    disposed = true;
    unawaited(interpreter.close());
  }

  static Future<TimelapseService> download({
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final cacheDir = await getApplicationCacheDirectory();
    final filePath = p.join(cacheDir.path, 'film.tflite');
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        await Dio().download(modelUrl, filePath,
          onReceiveProgress: onReceiveProgress,
          cancelToken: cancelToken,
        );
      }

      final (options, delegate) = InterpreterFactory.create(
        PerformanceConfig.xnnpack(numThreads: 4),
      );
      final interpreter = Interpreter.fromFile(file, options: options);
      return TimelapseService(
        outputTensors: interpreter.getOutputTensors().toList(),
        interpreter: await IsolateInterpreter.create(address: interpreter.address),
      );
    } catch (e) {
      await file.delete();
      rethrow;
    }
  }

  static Future<TimelapseService> load() async {
    final (options, delegate) = InterpreterFactory.create(
      PerformanceConfig.xnnpack(numThreads: 4),
    );
    final interpreter = await Interpreter.fromAsset(assetName, options: options);
    return TimelapseService(
      outputTensors: interpreter.getOutputTensors().toList(),
      interpreter: await IsolateInterpreter.create(address: interpreter.address),
    );
  }

  Future<Uint8List> generateImage({
    required img.Image firstImage,
    required img.Image secondImage,
    int? width,
    int? height,
    double delay = 0.5,
  }) async {
    final actualWidth = width ?? min(firstImage.width, secondImage.width);
    final actualHeight = height ?? min(firstImage.height, secondImage.height);

    final firstTensor = await _createInput(_resize(firstImage, actualWidth, actualHeight));
    final secondTensor = await _createInput(_resize(secondImage, actualWidth, actualHeight));

    final output = await _generateFrame(
      firstImage: firstTensor,
      secondImage: secondTensor,
      delay: delay,
    );
    final image = _decodeImage(output, actualWidth, actualHeight);
    return img.JpegEncoder().encode(image);
  }

  Future<Uint8List?> generateVideo({
    required img.Image firstImage,
    required img.Image secondImage,
    int? width,
    int? height,
    Duration duration = const Duration(seconds: 5),
    double fps = 24,
    ProgressCallback? onReceiveProgress,
  }) async {
    final actualWidth = width ?? min(firstImage.width, secondImage.width);
    final actualHeight = height ?? min(firstImage.height, secondImage.height);

    final firstTensor = await _createInput(_resize(firstImage, actualWidth, actualHeight));
    final secondTensor = await _createInput(_resize(secondImage, actualWidth, actualHeight));

    final totalFrames = (duration.inMilliseconds * fps / 1000).toInt();
    onReceiveProgress?.call(0, totalFrames + 1);
    final frames = <img.Image>[];
    for (final idx in Iterable.generate(totalFrames + 1)) {
      if (disposed) {
        return null;
      }
      final output = await _generateFrame(
        firstImage: firstTensor,
        secondImage: secondTensor,
        delay: idx / totalFrames,
      );
      if (disposed) {
        return null;
      }
      frames.add(_decodeImage(output, actualWidth, actualHeight));
      onReceiveProgress?.call(idx + 1, totalFrames + 1);
    }

    return _encodeGifFromImages(frames, fps);
  }

  static Future<Float32List> _createInput(img.Image image) async {
    final rgbData = Uint8List(image.width * image.height * 3);
    int idx = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        rgbData[idx++] = pixel.r.toInt();
        rgbData[idx++] = pixel.g.toInt();
        rgbData[idx++] = pixel.b.toInt();
      }
    }

    var tensor = TensorBuffer.fromUint8List(image.getBytes(), [image.height, image.width, 3]);
    final pipeline = TensorPipeline([
      ToTensorOp(normalize: true),
      TypeCastOp(DType.float32),
      UnsqueezeOp.batch(),
    ]);
    tensor = await pipeline.runAsync(tensor);
    return tensor.toChannelsLast().contiguous().dataAsFloat32List;
  }

  static img.Image _decodeImage(Float32List data, int width, int height) {
    final outputImage = img.Image(width: width, height: height);

    // Fill pixel data from tensor (clamping values to [0.0, 1.0] range)
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

  Future<Uint8List?> _encodeGifFromImages(List<img.Image> images, double fps) async {
    final encoder = img.GifEncoder();

    for (var image in images) {
      encoder.addFrame(image, duration: (1000 / fps).toInt());
    }

    final gifBytes = encoder.finish();
    if (gifBytes == null) {
      return null;
    }
    return Uint8List.fromList(gifBytes);
  }

  Future<Float32List> _generateFrame({
    required Float32List firstImage,
    required Float32List secondImage,
    required double delay,
  }) async {
    final timeData = Float32List.fromList([0.5]);
    final inputs = [
      timeData.buffer.asUint8List(),
      firstImage.buffer.asUint8List(),
      secondImage.buffer.asUint8List(),
    ];

    final outputs = <int, Object>{};
    for (int i = 0; i < outputTensors.length; i++) {
      final tensor = outputTensors[i];
      outputs[i] = TensorBuffer.zeros(tensor.shape);
    }

    await interpreter.runForMultipleInputs(inputs, outputs);

    final output = outputs[1] as TensorBuffer;
    return output.dataAsFloat32List;
  }

  static img.Image _resize(img.Image image, int width, int height) {
    if (image.width == width && image.height == height) {
      return image;
    }

    return img.copyResize(image,
      width: width,
      height: height,
      maintainAspect: false,
    );
  }
}