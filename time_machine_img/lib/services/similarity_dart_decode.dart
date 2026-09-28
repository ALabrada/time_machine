import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'picture_fingerprint.dart';

/// Reduces an encoded picture to a [StructuralFingerprint] using
/// `package:image`.
///
/// This is the *slow* path: a full-resolution decode in Dart, on whichever
/// isolate calls it. It is the whole implementation on native — where it runs
/// inside `Isolate.run` and so never touches the UI isolate — and it is only
/// reached on the web when the browser cannot decode natively for us (see
/// `_similarity_platform_web.dart`), where it is a fallback that preserves the
/// previous behaviour rather than an improvement.
///
/// The expensive full-resolution passes are kept to a minimum. `package:image`
/// compiles decode and crop, and [_areaAverageBlock] reduces the crop straight
/// to [fingerprintSize] x [fingerprintSize] in one pass, so unlike the previous
/// implementation there is no full-resolution grayscale pass and no
/// full-resolution `convert(numChannels: 3)` copy.
StructuralFingerprint? fingerprintWithDartDecoder({
  required Uint8List bytes,
  required Rectangle<num> viewPort,
  required Rectangle<num> intersection,
}) {
  final img.Image image;
  try {
    // `decodeImage` returns null for an unrecognised format but *throws* a
    // RangeError on truncated data, so a partially written cache file has to be
    // caught here rather than propagating out of a comparison.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    image = decoded;
  } on Object {
    return null;
  }
  // The downscale sums per channel, so a non-3-channel source is normalized
  // once here rather than relying on every subsequent call site to do it.
  final source = image.numChannels == 3 ? image : image.convert(numChannels: 3);

  final crop = resolveSimilarityCrop(
    width: source.width,
    height: source.height,
    viewPort: viewPort,
    intersection: intersection,
  );
  if (crop == null || crop.isSmallerThanGrid) {
    return null;
  }

  final cropped = img.copyCrop(
    source,
    x: crop.left,
    y: crop.top,
    width: crop.width,
    height: crop.height,
  );

  return StructuralFingerprint.fromRgbBlock(_areaAverageBlock(cropped));
}

/// Area-averages [image] down to a [fingerprintSize] x [fingerprintSize] block
/// of sRGB, returning [fingerprintSamples] * 3 bytes, row-major.
///
/// This is written out rather than delegated to `image`'s
/// `Interpolation.average` for two reasons:
///
/// * **Rounding.** `copyResize` writes its averages through `setPixelRgba`,
///   which calls `toInt()` and therefore *truncates*, whereas the browser's
///   `getImageData` *rounds*. A systematic half-LSB bias is not noise, and the
///   browser is the side that has to be matched.
/// * **Cell geometry.** `Interpolation.average` derives its cell boundaries
///   with `(x * dx).toInt()`, which truncates and so does not tile the source
///   exactly. Here each source pixel contributes in proportion to the area it
///   shares with a cell, which is what the canvas rasterizer does.
///
/// The whole image maps onto the grid, so only its own dimensions matter — and
/// note `copyCrop` re-origins the image at (0, 0), so the grid is indexed in the
/// cropped image's coordinates, not the source's.
///
/// The loop runs once over the crop — the same order of work as the
/// `copyResize` call it replaces, and equally Dart — inside `Isolate.run` on
/// native, so none of it touches the UI isolate.
Uint8List _areaAverageBlock(img.Image image) {
  const n = fingerprintSize;
  const sampleCount = fingerprintSamples;
  final block = Uint8List(sampleCount * 3);
  final sums = Float64List(sampleCount * 3);
  final weights = Float64List(sampleCount);

  final width = image.width.toDouble();
  final height = image.height.toDouble();
  if (width <= 0 || height <= 0) {
    return block;
  }
  // Cell `k` spans [k / n, (k + 1) / n) of the image. The grid divides the
  // image exactly, so every pixel falls inside the image and needs no clamping
  // against it; only the cell index needs bounds checking, which `cellIndex`
  // does, including the case of a boundary landing exactly on the trailing edge.
  final cellWidth = width / n;
  final cellHeight = height / n;

  int cellIndex(double offset, double cellSize) {
    final index = (offset / cellSize).floor();
    return index < 0 ? 0 : (index > n - 1 ? n - 1 : index);
  }

  for (var y = 0; y < image.height; y++) {
    final rowBottom = y + 1.0;
    // A pixel row overlaps at most two cell rows; a boundary row contributes a
    // fraction to each of them.
    final firstRow = cellIndex(y.toDouble(), cellHeight);
    final lastRow = cellIndex(rowBottom, cellHeight)
        .clamp(firstRow, n - 1)
        .toInt();

    for (var x = 0; x < image.width; x++) {
      final colRight = x + 1.0;
      final firstCol = cellIndex(x.toDouble(), cellWidth);
      final lastCol = cellIndex(colRight, cellWidth)
          .clamp(firstCol, n - 1)
          .toInt();

      final pixel = image.getPixel(x, y);
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;

      for (var row = firstRow; row <= lastRow; row++) {
        final weightY =
            min(rowBottom, (row + 1) * cellHeight) - max(y.toDouble(), row * cellHeight);
        if (weightY <= 0) {
          continue;
        }
        for (var column = firstCol; column <= lastCol; column++) {
          final weightX = min(colRight, (column + 1) * cellWidth) -
              max(x.toDouble(), column * cellWidth);
          if (weightX <= 0) {
            continue;
          }
          final weight = weightX * weightY;
          final cell = row * n + column;
          final offset = cell * 3;
          sums[offset] += r * weight;
          sums[offset + 1] += g * weight;
          sums[offset + 2] += b * weight;
          weights[cell] += weight;
        }
      }
    }
  }

  for (var cell = 0; cell < sampleCount; cell++) {
    final weight = weights[cell];
    if (weight <= 0) {
      continue;
    }
    final offset = cell * 3;
    block[offset] = (sums[offset] / weight).round().clamp(0, 255);
    block[offset + 1] = (sums[offset + 1] / weight).round().clamp(0, 255);
    block[offset + 2] = (sums[offset + 2] / weight).round().clamp(0, 255);
  }
  return block;
}

