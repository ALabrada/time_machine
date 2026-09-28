/// Cross-platform parity for the decode-and-reduce step.
///
/// On the Dart VM, `computeSimilarityFingerprint` resolves to the native
/// backend, so this compares native against the same exact reducer and mostly
/// guards the shared arithmetic. The test earns its keep on the web, where
/// `computeSimilarityFingerprint` resolves to the *canvas* backend and is
/// compared against [fingerprintWithDartDecoder] — the exact area average
/// native uses. Run it with:
///
/// ```sh
/// flutter test --platform chrome test/services/similarity_platform_parity_test.dart
/// ```
///
/// That is the only check that the two platforms agree. Without it a web-only
/// divergence is invisible: the ordinary unit tests exercise the same code the
/// native build runs, and the browser build's numbers are never compared to
/// anything. The defect this file was written for was exactly that — a single
/// `drawImage` reducing a ~4000 px crop straight to 32 px disagreed with the
/// native area average by up to 0.198, and no test noticed.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:time_machine_img/services/_similarity_platform.dart';
import 'package:time_machine_img/services/similarity_dart_decode.dart';

/// The web reduction lands within ~0.002 of native on real photographs. This
/// budget sits a decade below the 0.198 regression it guards against, so a
/// loosened canvas filter fails loudly without making the test flaky.
const double _tolerance = 0.02;

/// A deterministic pseudo-random source, so failures reproduce.
class _Noise {
  int _state;
  _Noise(this._state);

  int next(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}

/// Builds an image whose content is hostile to a filtered downscale.
///
/// The failure mode being guarded against is *aliasing*: a step that samples
/// too few source pixels per output cell loses high-frequency detail. White
/// noise is too easy, because it averages out at any reasonable filter. Fine
/// periodic structure is the hard case — it survives resampling at some phases
/// and cancels at others, so a filter with the wrong support produces a visibly
/// wrong cell rather than indistinguishable noise.
img.Image _aliasingHostile({
  required int width,
  required int height,
  required int seed,
}) {
  final random = _Noise(seed);
  final image = img.Image(width: width, height: height, numChannels: 3);
  final period = 5 + random.next(7);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Fine diagonal striping, a coarse checker, and a smooth ramp, so that
      // no single filter phase can conspire to look correct.
      final stripe = ((x + y) % period) * 255 ~/ period;
      final checker = ((x ~/ 23) + (y ~/ 19)).isEven ? 210 : 40;
      final ramp = (x * 255 ~/ width + y * 255 ~/ height) ~/ 2;
      final jitter = random.next(16);
      image.setPixelRgb(
        x,
        y,
        (stripe + jitter) % 256,
        (checker + jitter) % 256,
        (ramp + jitter) % 256,
      );
    }
  }
  return image;
}

/// Smooth, low-frequency content: the opposite extreme, which catches a filter
/// whose support is too *wide*, since that blurs away real structure.
img.Image _smoothScene({required int width, required int height}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final band = (y * 12 ~/ height) % 3;
      final r = band == 0 ? 235 : (band == 1 ? 120 : 30);
      final g = band == 0 ? 225 : (band == 1 ? 130 : 40);
      final b = band == 0 ? 210 : (band == 1 ? 150 : 60);
      final shade = x * 40 ~/ width;
      image.setPixelRgb(x, y, r - shade, g - shade ~/ 2, b - shade ~/ 3);
    }
  }
  return image;
}

Uint8List _encode(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 92));

/// Runs both backends over the same bytes, with the viewport covering the whole
/// picture so the crop itself is the interesting part.
Future<(PictureFingerprint?, PictureFingerprint?)> _bothPaths(
  Uint8List bytes,
) async {
  final viewPort = Rectangle<num>(0, 0, 1, 1);
  final intersection = Rectangle<num>(0, 0, 1, 1);
  return (
    fingerprintWithDartDecoder(
      bytes: bytes,
      viewPort: viewPort,
      intersection: intersection,
    ),
    await computeSimilarityFingerprint(
      bytes: bytes,
      viewPort: viewPort,
      intersection: intersection,
    ),
  );
}

void main() {
  group('platform parity', () {
    test('fine high-frequency content survives both reductions alike', () async {
      // 3200 px against a 512 px intermediate is a ~6x browser step — the
      // regime the defect lived in.
      final bytes = _encode(
        _aliasingHostile(width: 3200, height: 2000, seed: 3),
      );
      final (native, platform) = await _bothPaths(bytes);

      expect(native, isNotNull);
      expect(platform, isNotNull);
      final delta = (native!.similarityTo(platform!) - 1).abs();
      expect(delta, lessThan(_tolerance),
          reason: 'fingerprint differs by $delta between backends');
    });

    test('a second, differently-seeded high-frequency picture agrees', () async {
      final bytes = _encode(
        _aliasingHostile(width: 2400, height: 1600, seed: 91),
      );
      final (native, platform) = await _bothPaths(bytes);

      expect(native, isNotNull);
      expect(platform, isNotNull);
      final delta = (native!.similarityTo(platform!) - 1).abs();
      expect(delta, lessThan(_tolerance),
          reason: 'fingerprint differs by $delta between backends');
    });

    test('smooth content agrees', () async {
      final bytes = _encode(_smoothScene(width: 1600, height: 1200));
      final (native, platform) = await _bothPaths(bytes);

      expect(native, isNotNull);
      expect(platform, isNotNull);
      final delta = (native!.similarityTo(platform!) - 1).abs();
      expect(delta, lessThan(_tolerance),
          reason: 'fingerprint differs by $delta between backends');
    });

    test('a small picture agrees', () async {
      // Near the grid size, so the crop spans only a few cells and the
      // partial-edge weighting in the shared reducer is what is under test.
      final bytes = _encode(_smoothScene(width: 96, height: 64));
      final (native, platform) = await _bothPaths(bytes);

      expect(native, isNotNull);
      expect(platform, isNotNull);
      final delta = (native!.similarityTo(platform!) - 1).abs();
      expect(delta, lessThan(_tolerance),
          reason: 'fingerprint differs by $delta between backends');
    });

    test('a picture smaller than the grid is rejected on every platform',
        () async {
      final bytes = _encode(_smoothScene(width: 20, height: 12));
      final (native, platform) = await _bothPaths(bytes);

      expect(native, isNull);
      expect(platform, isNull);
    });

    test('a truncated file is fingerprinted the same way on both platforms',
        () async {
      // `package:image` decodes whatever intact prefix a truncated JPEG has, so
      // this is a recoverable picture rather than a missing one. Engines differ
      // on how much they salvage, so the assertion is parity, not a particular
      // outcome — but both platforms must land on the same answer.
      final bytes = _encode(_smoothScene(width: 512, height: 512));
      final (native, platform) =
          await _bothPaths(Uint8List.sublistView(bytes, 0, bytes.length ~/ 3));

      if (native == null) {
        expect(platform, isNull);
      } else {
        expect(platform, isNotNull,
            reason: 'web reports no fingerprint where native has one');
        final delta = (native.similarityTo(platform!) - 1).abs();
        expect(delta, lessThan(_tolerance),
            reason: 'fingerprint differs by $delta on a truncated file');
      }
    });
  });
}
