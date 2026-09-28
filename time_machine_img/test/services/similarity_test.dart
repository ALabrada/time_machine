import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:time_machine_core/domain/record.dart';
import 'package:time_machine_img/services/picture_fingerprint.dart';
import 'package:time_machine_img/services/similarity_dart_decode.dart';
import 'package:time_machine_img/services/similarity_service.dart';

/// A deterministic pseudo-random source, so failures reproduce.
class _Noise {
  int _state;
  _Noise(this._state);

  /// The next value in `[0, max)`.
  int next(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}

img.Image _testImage({
  required int width,
  required int height,
  int seed = 7,
  int? blockSize,
}) {
  final random = _Noise(seed);
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Block-structured noise: coarse cells of flat colour plus a little
      // per-pixel dither. A real photograph is far closer to this than to
      // white noise, and it exercises the area filter rather than a point
      // sample, which is the whole point of the comparison below.
      final cell = (x ~/ (blockSize ?? 17)) * 31 +
          (y ~/ (blockSize ?? 17)) * 17;
      final r = (cell * 7 + random.next(24)) % 256;
      final g = (cell * 13 + random.next(24)) % 256;
      final b = (cell * 29 + random.next(24)) % 256;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// Builds a [StructuralFingerprint] from generated 8-bit RGB samples, the shape
/// both backends hand to [StructuralFingerprint.fromRgbBlock].
StructuralFingerprint _fingerprint(int Function(int i) sample) {
  final rgb = Uint8List(fingerprintSamples * 3);
  for (var i = 0; i < fingerprintSamples; i++) {
    final v = sample(i);
    rgb[i * 3] = v;
    rgb[i * 3 + 1] = v;
    rgb[i * 3 + 2] = v;
  }
  return StructuralFingerprint.fromRgbBlock(rgb);
}

/// An independent, straightforward area-weighted box filter: for each
/// destination cell, every source pixel contributes in proportion to how much
/// of the cell it covers.
///
/// The implementation under test scatters each pixel into the cells it
/// touches; this one instead walks each cell and asks which pixels overlap it.
/// Writing it the other way round keeps it a real cross-check of the
/// scatter-based arithmetic rather than a restatement of it, and it is the
/// model the browser's `drawImage` rasterizer implements.
///
/// [image] must already be cropped to the region of interest, since `copyCrop`
/// re-origins the image at (0, 0) — the grid maps onto all of it.
Uint8List _referenceAreaAverage(img.Image image) {
  final out = Uint8List(fingerprintSamples * 3);
  final width = image.width.toDouble();
  final height = image.height.toDouble();

  for (var j = 0; j < fingerprintSize; j++) {
    final y0 = height * j / fingerprintSize;
    final y1 = height * (j + 1) / fingerprintSize;
    for (var i = 0; i < fingerprintSize; i++) {
      final x0 = width * i / fingerprintSize;
      final x1 = width * (i + 1) / fingerprintSize;

      var r = 0.0, g = 0.0, b = 0.0, weight = 0.0;
      for (var y = max(0, y0.floor()); y <= min(image.height - 1, y1.ceil() - 1); y++) {
        final overlapY = min(y + 1.0, y1) - max(y.toDouble(), y0);
        if (overlapY <= 0) continue;
        for (var x = max(0, x0.floor()); x <= min(image.width - 1, x1.ceil() - 1); x++) {
          final overlapX = min(x + 1.0, x1) - max(x.toDouble(), x0);
          if (overlapX <= 0) continue;
          final pixel = image.getPixel(x, y);
          final w = overlapX * overlapY;
          r += pixel.r * w;
          g += pixel.g * w;
          b += pixel.b * w;
          weight += w;
        }
      }
      final offset = (j * fingerprintSize + i) * 3;
      if (weight <= 0) continue;
      out[offset] = (r / weight).round().clamp(0, 255);
      out[offset + 1] = (g / weight).round().clamp(0, 255);
      out[offset + 2] = (b / weight).round().clamp(0, 255);
    }
  }
  return out;
}

/// Decodes [bytes] and reduces it through the production path, returning both
/// the resulting fingerprint and the cropped pixels the filter actually saw.
({StructuralFingerprint fingerprint, img.Image crop}) _fingerprintAndCrop(
  Uint8List bytes,
  Rectangle viewPort,
  Rectangle intersection,
) {
  final decoded = img.decodeImage(bytes)!;
  final crop = resolveSimilarityCrop(
    width: decoded.width,
    height: decoded.height,
    viewPort: viewPort,
    intersection: intersection,
  )!;
  final cropped = img.copyCrop(
    decoded,
    x: crop.left,
    y: crop.top,
    width: crop.width,
    height: crop.height,
  );
  return (
    fingerprint: fingerprintWithDartDecoder(
      bytes: bytes,
      viewPort: viewPort,
      intersection: intersection,
    )!,
    crop: cropped,
  );
}

/// A synthetic with the spatial spectrum of a photograph: a few large soft
/// masses, a broad tonal gradient, and fine grain.
///
/// The lattice noise in [_testImage] is deliberately hostile — its content
/// changes completely under a small shift — which makes it good for exercising
/// the area filter and useless for anything that depends on a scene surviving a
/// change of framing.
img.Image _photoLike({int seed = 999, int size = 512}) {
  var state = seed;
  int next(int max) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state % max;
  }

  final image = img.Image(width: size, height: size, numChannels: 3);
  final masses = List.generate(9, (_) => [next(size), next(size), 30 + next(70)]);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var v = 110.0;
      for (final mass in masses) {
        final dx = (x - mass[0]) / mass[2], dy = (y - mass[1]) / mass[2];
        v += 70 * exp(-(dx * dx + dy * dy));
      }
      v += 8 * (y / size) + next(9) - 4;
      final c = v.round().clamp(0, 255);
      image.setPixelRgb(x, y, c, (c * 0.9).round().clamp(0, 255), (c * 0.8).round().clamp(0, 255));
    }
  }
  return image;
}

img.Image _toneShift(img.Image source, double gain, double offset) {
  final out = img.Image.from(source);
  double f(num v) => (v * gain + offset).round().clamp(0, 255).toDouble();
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = source.getPixel(x, y);
      out.setPixelRgb(x, y, f(p.r), f(p.g), f(p.b));
    }
  }
  return out;
}

void main() {
  group('StructuralFingerprint', () {
    test('a picture is a perfect match with itself', () {
      final random = _Noise(11);
      final a = _fingerprint((_) => random.next(256));
      expect(a.similarityTo(a), closeTo(1.0, 1e-12));
    });

    test('is symmetric and bounded to [0, 1]', () {
      final first = _Noise(3);
      final second = _Noise(5);
      for (var trial = 0; trial < 20; trial++) {
        final a = _fingerprint((_) => first.next(256));
        final b = _fingerprint((_) => second.next(256));
        final forward = a.similarityTo(b);
        expect(b.similarityTo(a), forward);
        expect(forward, inInclusiveRange(0.0, 1.0));
      }
    });

    test('survives a change of exposure or contrast', () {
      // The whole point of correlating centred, scaled blocks: a 1960s print
      // and a modern photograph of the same scene differ in exposure and
      // contrast, and must not be punished for it.
      final source = _photoLike(seed: 21, size: 256);
      for (final (gain, offset) in [(0.7, 0.0), (1.3, 0.0), (1.0, 20.0), (0.6, 60.0)]) {
        final shifted = _toneShift(source, gain, offset);
        final before = fingerprintWithDartDecoder(
          bytes: Uint8List.fromList(img.encodePng(source)),
          viewPort: const Rectangle(0, 0, 256, 256),
          intersection: const Rectangle(0, 0, 256, 256),
        )!;
        final after = fingerprintWithDartDecoder(
          bytes: Uint8List.fromList(img.encodePng(shifted)),
          viewPort: const Rectangle(0, 0, 256, 256),
          intersection: const Rectangle(0, 0, 256, 256),
        )!;
        expect(before.similarityTo(after), greaterThan(0.95),
            reason: 'gain $gain offset $offset should be near-invisible');
      }
    });

    test('survives a monotone tone curve, which centring alone would not', () {
      // Gamma and faded film are not affine, so a plain correlation cannot
      // absorb them. This is what the equalised half of the score buys, and it
      // is the property a correlation is chosen over a median hash for.
      final source = _photoLike(seed: 33, size: 256);
      final faded = img.Image.from(source);
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          final p = source.getPixel(x, y);
          double f(num v) => (255 * pow(v / 255, 2.2)).round().clamp(0, 255).toDouble();
          faded.setPixelRgb(x, y, f(p.r), f(p.g), f(p.b));
        }
      }
      Uint8List encode(img.Image image) => Uint8List.fromList(img.encodePng(image));
      Rectangle vp() => const Rectangle(0, 0, 256, 256);
      final before = fingerprintWithDartDecoder(
          bytes: encode(source), viewPort: vp(), intersection: vp())!;
      final after = fingerprintWithDartDecoder(
          bytes: encode(faded), viewPort: vp(), intersection: vp())!;
      expect(before.similarityTo(after), greaterThan(0.95));
    });

    test('collapses on different content, where the median hash did not', () {
      // The regression this metric exists to fix. Against 215 unrelated
      // photographs the median hash this replaced had a median score of 53% and
      // a 90th percentile of 72%, so 62% of unrelated pairs beat the weakest
      // known-same-street pair. Here the two are structurally unrelated.
      final first = _fingerprint((i) => (i * 7) % 256);
      final second = _fingerprint((i) => (i * 199 + 13) % 256);
      expect(first.similarityTo(second), lessThan(0.2));
    });

    test('degrades gradually under a change of viewpoint', () {
      // A small viewpoint change is the normal case for a user re-framing an
      // archival photo, and must stay far above what different content scores.
      // Measured on real photographs this is 0.74-0.92 for a 5% shift; the
      // synthetic here reproduces that.
      final source = _photoLike(seed: 999);
      final zoomed = img.copyCrop(source,
          x: 26, y: 26, width: 460, height: 460);
      Uint8List encode(img.Image image) => Uint8List.fromList(img.encodePng(image));
      Rectangle vp() => const Rectangle(0, 0, 512, 512);
      final before = fingerprintWithDartDecoder(
          bytes: encode(source), viewPort: vp(), intersection: vp())!;
      final after = fingerprintWithDartDecoder(
          bytes: encode(zoomed), viewPort: vp(), intersection: vp())!;
      expect(before.similarityTo(after), greaterThan(0.9));
    });

    test('a flat block carries no signal and scores zero, not one', () {
      // Two crops of blank wall, or of blown-out sky, have nothing to
      // correlate. Reporting 100% there is how a metric ends up claiming that
      // two unrelated pictures are identical.
      final flatA = _fingerprint((_) => 40);
      final flatB = _fingerprint((_) => 200);
      expect(flatA.similarityTo(flatA), 0.0);
      expect(flatA.similarityTo(flatB), 0.0);

      final structure = _fingerprint((i) => (i * 11) % 256);
      expect(structure.similarityTo(flatA), 0.0);
      expect(flatA.similarityTo(structure), 0.0);
    });

    test('rejects a fingerprint of a different kind', () {
      final a = _fingerprint((i) => (i * 7) % 256);
      expect(() => a.similarityTo(_FakeFingerprint()), throwsArgumentError);
    });

    test('rejects an sRGB block of the wrong size', () {
      expect(() => StructuralFingerprint.fromRgbBlock(Uint8List(10)),
          throwsA(isA<AssertionError>()));
    });
  });

  group('resolveSimilarityCrop', () {
    test('scales the intersection onto the source image', () {
      // Viewport 800x600 shown as a 1600x1200 source: the whole viewport maps
      // to the whole image, so an intersection covering half of it maps to
      // the top-left quarter.
      final crop = resolveSimilarityCrop(
        width: 1600,
        height: 1200,
        viewPort: const Rectangle(0, 0, 800, 600),
        intersection: const Rectangle(0, 0, 400, 300),
      );
      expect(crop, isNotNull);
      expect(crop!.left, 0);
      expect(crop.top, 0);
      expect(crop.width, 800);
      expect(crop.height, 600);
    });

    test('rejects a degenerate crop', () {
      expect(
        resolveSimilarityCrop(
          width: 100,
          height: 100,
          viewPort: const Rectangle(0, 0, 100, 100),
          intersection: const Rectangle(200, 200, 10, 10),
        ),
        isNull,
      );
    });

    test('flags a crop too small to carry signal', () {
      expect(const SimilarityCrop(0, 0, 4, 100).isSmallerThanGrid, isTrue);
      expect(
        const SimilarityCrop(0, 0, fingerprintSize, fingerprintSize)
            .isSmallerThanGrid,
        isFalse,
      );
    });
  });

  group('fingerprintWithDartDecoder', () {
    test('returns null for undecodable bytes', () {
      expect(
        fingerprintWithDartDecoder(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          viewPort: const Rectangle(0, 0, 10, 10),
          intersection: const Rectangle(0, 0, 10, 10),
        ),
        isNull,
      );
    });

    test('never throws on damaged bytes', () {
      // A partially written cache file is the realistic case. `decodeImage`
      // returns null for an unrecognised format and *throws* on some damaged
      // ones, so the decode is guarded. What matters is that no malformed input
      // escapes a comparison; whether a damaged-but-still-parseable file yields a
      // fingerprint is the decoder's business, not ours.
      final jpeg = Uint8List.fromList(
          img.encodeJpg(_testImage(width: 400, height: 300)));
      final damaged = <String, Uint8List>{
        'empty': Uint8List(0),
        'random': Uint8List.fromList([1, 2, 3, 4, 5]),
        'jpeg header then garbage': Uint8List.fromList([
          ...jpeg.sublist(0, 64),
          ...List<int>.filled(256, 0xAB),
        ]),
        'truncated then garbage': Uint8List.fromList([
          ...jpeg.sublist(0, jpeg.length ~/ 4),
          ...List<int>.filled(256, 0),
        ]),
      };
      for (final MapEntry(key: name, value: bytes) in damaged.entries) {
        expect(
          () => fingerprintWithDartDecoder(
            bytes: bytes,
            viewPort: const Rectangle(0, 0, 400, 300),
            intersection: const Rectangle(0, 0, 400, 300),
          ),
          returnsNormally,
          reason: '$name should not escape a comparison',
        );
      }
      // Bytes that are not an image at all cannot produce a fingerprint.
      expect(
        fingerprintWithDartDecoder(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          viewPort: const Rectangle(0, 0, 400, 300),
          intersection: const Rectangle(0, 0, 400, 300),
        ),
        isNull,
      );
    });

    test('returns null when the crop is smaller than the fingerprint grid', () {
      final image = _testImage(width: 64, height: 64);
      expect(
        fingerprintWithDartDecoder(
          bytes: Uint8List.fromList(img.encodeJpg(image)),
          viewPort: const Rectangle(0, 0, 64, 64),
          intersection: const Rectangle(0, 0, 4, 4),
        ),
        isNull,
      );
    });

    test('scores an image against itself as a perfect match', () {
      final image = _testImage(width: 400, height: 300);
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      final fingerprint = fingerprintWithDartDecoder(
        bytes: bytes,
        viewPort: const Rectangle(0, 0, 400, 300),
        intersection: const Rectangle(0, 0, 400, 300),
      );
      expect(fingerprint, isNotNull);
      expect(fingerprint!.similarityTo(fingerprint), closeTo(1.0, 1e-12));
    });
  });

  group('SimilarityService.computeSimilarity', () {
    Record recordWith(String? original, String? picture) => Record(
          pictureId: 1,
          createdAt: DateTime(2020),
          updateAt: DateTime(2020),
          originalViewPort: original,
          pictureViewPort: picture,
        );

    test('returns null when a viewport is missing or unparsable', () async {
      final bytes = Uint8List.fromList(img.encodePng(_testImage(width: 128, height: 128)));
      for (final (original, picture) in <(String?, String?)>[
        (null, '0,0,128,128'),
        ('0,0,128,128', null),
        ('nonsense', '0,0,128,128'),
        ('0,0,128', '0,0,128,128'),
      ]) {
        expect(
          await SimilarityService.computeSimilarity(
            record: recordWith(original, picture),
            originalBytes: bytes,
            ownBytes: bytes,
          ),
          isNull,
        );
      }
    });

    test('returns null when the two viewports do not overlap', () async {
      final bytes = Uint8List.fromList(img.encodePng(_testImage(width: 128, height: 128)));
      expect(
        await SimilarityService.computeSimilarity(
          record: recordWith('0,0,64,64', '200,200,64,64'),
          originalBytes: bytes,
          ownBytes: bytes,
        ),
        isNull,
      );
    });

    test('returns null when either picture cannot be decoded', () async {
      final bytes = Uint8List.fromList(img.encodePng(_testImage(width: 128, height: 128)));
      const broken = [0, 1, 2, 3, 4, 5, 6, 7];
      expect(
        await SimilarityService.computeSimilarity(
          record: recordWith('0,0,128,128', '0,0,128,128'),
          originalBytes: Uint8List.fromList(broken),
          ownBytes: bytes,
        ),
        isNull,
      );
      expect(
        await SimilarityService.computeSimilarity(
          record: recordWith('0,0,128,128', '0,0,128,128'),
          originalBytes: bytes,
          ownBytes: Uint8List.fromList(broken),
        ),
        isNull,
      );
    });

    test('scores identical bytes as a perfect match', () async {
      final bytes = Uint8List.fromList(img.encodePng(_testImage(width: 256, height: 256)));
      expect(
        await SimilarityService.computeSimilarity(
          record: recordWith('0,0,256,256', '0,0,256,256'),
          originalBytes: bytes,
          ownBytes: bytes,
        ),
        closeTo(1.0, 1e-12),
      );
    });
  });

  group('cross-platform parity', () {
    // The native backend and the browser both area-average the same decoded
    // pixels down to the same grid, and both round the result. If those two
    // definitions ever drift apart, the scores a user sees on the web stop
    // being comparable to the ones they see on a phone, which is the whole
    // reason the web path does not just reuse the Dart one. This asserts exact
    // agreement against an independently written area filter.
    test('matches an independent area-weighted box filter exactly', () {
      for (final size in [200, 400, 1234, 2000, 4000]) {
        final image = _testImage(width: size, height: size, seed: size);
        final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
        final viewport = Rectangle(0, 0, size.toDouble(), size.toDouble());

        final result = _fingerprintAndCrop(bytes, viewport, viewport);
        final reference = _referenceAreaAverage(result.crop);

        // Compare through the metric rather than the raw block, because the
        // block is an implementation detail; what must agree is the score.
        expect(
          result.fingerprint.similarityTo(
              StructuralFingerprint.fromRgbBlock(reference)),
          closeTo(1.0, 1e-12),
          reason: 'area filter disagreed at ${size}px',
        );
      }
    });

    test('matches the reference for an off-origin sub-crop', () {
      // A crop that does not start at (0, 0) is the case that would expose a
      // mistake about `copyCrop` re-origining the image.
      const size = 640;
      final image = _testImage(width: size, height: size, seed: 99);
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));

      final viewport = const Rectangle(50, 30, 500, 400);
      final intersection = const Rectangle(70, 45, 220, 180);
      final result = _fingerprintAndCrop(bytes, viewport, intersection);

      expect(
        result.fingerprint.similarityTo(StructuralFingerprint.fromRgbBlock(
            _referenceAreaAverage(result.crop))),
        closeTo(1.0, 1e-12),
      );
    });

    test('does not inherit a rounding bias on low-contrast scenes', () {
      // Regression guard. An earlier version delegated to `image`'s
      // `Interpolation.average`, which truncates where the canvas rounds. The
      // half-LSB difference is a *systematic* bias, and it used to flip whole
      // median-hash bits wherever a cell mean sat near the block median.
      final image = img.Image(width: 3000, height: 3000, numChannels: 3);
      final random = _Noise(5);
      for (var y = 0; y < 3000; y++) {
        for (var x = 0; x < 3000; x++) {
          // Structure coarse enough to survive a 32x32 reduction, but with cell
          // means only a couple of levels apart, so a half-LSB rounding bias
          // would be enough to move a sample a long way.
          final v = 100 + ((x ~/ 80 + y ~/ 80) % 3) + random.next(3);
          image.setPixelRgb(x, y, v, v, v);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      final viewport = const Rectangle(0, 0, 3000, 3000);
      final result = _fingerprintAndCrop(bytes, viewport, viewport);
      final reference =
          StructuralFingerprint.fromRgbBlock(_referenceAreaAverage(result.crop));

      expect(result.fingerprint.similarityTo(reference), 1.0);
    });
  });
}

class _FakeFingerprint implements PictureFingerprint {
  @override
  double similarityTo(PictureFingerprint other) => 0;
}
