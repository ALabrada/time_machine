import 'dart:math';
import 'dart:typed_data';

import 'package:time_machine_core/utils/file_path.dart';

/// Side length, in pixels, of the block every backend reduces a picture to.
///
/// 32 is chosen so that a cell is small enough to carry local structure — the
/// roads, rooflines and building edges that identify a place — while the whole
/// block is small enough that the cross-platform contract can be checked
/// exactly (see [StructuralFingerprint]).
const int fingerprintSize = 32;

/// Number of samples in the block, and the length of the descriptor built
/// from it.
const int fingerprintSamples = fingerprintSize * fingerprintSize;

/// A picture reduced to a fixed-length, comparable summary.
///
/// This is the seam a different kind of similarity could be added behind —
/// a learned embedding, say, which is better at "these two show the same kind
/// of thing" but needs a model, an inference runtime and, on the web, WASM.
/// Everything above this interface (the service, the controller, the page) is
/// written against the interface only, so swapping implementations is a change
/// to the factory in [StructuralFingerprint.fromRgbBlock] and nothing else.
abstract interface class PictureFingerprint {
  /// How alike two pictures are, in `[0, 1]`.
  double similarityTo(PictureFingerprint other);
}

/// An axis-aligned crop rectangle, in source-image pixel coordinates.
class SimilarityCrop {
  const SimilarityCrop(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  /// Whether the rectangle is too small to carry any signal. A crop narrower
  /// or shorter than the fingerprint grid is rejected on **every** platform
  /// rather than upscaled, so a degenerate record reports no similarity instead
  /// of an arbitrary one.
  bool get isSmallerThanGrid =>
      width < fingerprintSize || height < fingerprintSize;
}

/// Structural similarity: how alike two pictures are in the *arrangement* of
/// their light and dark, regardless of colour, exposure or contrast.
///
/// ## Why not a perceptual hash
///
/// The obvious cheap metric — reduce to a small grid, threshold every cell
/// against the median, count differing bits — is what this replaced, and it does
/// not work for pictures taken decades apart. Two reasons, both of which showed
/// up immediately in real use:
///
/// * **It is a bang-bang quantizer.** Each of the 64 samples becomes a single
///   bit, so a difference of one part in 255 in a cell can flip a whole bit.
///   Measured on real records, a 2-LSB disagreement between two decoders of the
///   *same* file flipped 20 of 64 bits — a 31% swing in the score. Any residual
///   numerical disagreement, from any cause, becomes a cliff.
/// * **It has no floor and no gradient.** Two unrelated images differ in about
///   half their bits *by construction*, so "unrelated" scores ~50% and
///   "same street" scored ~75%: the entire useful range of the metric was
///   50–75%. Measured over 215 unrelated photographs, that metric's median was
///   53% and its 90th percentile 72%, so **62% of unrelated pairs scored at
///   least as high as the weakest of the three known-same-street pairs**. A
///   score that a random photograph pair usually beats is not a similarity
///   measure, whatever it is called.
///
/// A correlation has neither problem. It is continuous, so small numeric
/// differences produce small score differences, and it is centred and scaled,
/// so an unrelated pair lands near zero instead of near a coin toss. On an
/// equivalent set of unrelated photographs the median dropped from 53% to
/// 12%, and the whole distribution moved down rather than just its midpoint.
///
/// ## What it is, precisely
///
/// A [fingerprintSize] x [fingerprintSize] block of luminance, correlated with
/// the other picture's block. Two things make that appropriate for photographs
/// of the same place taken years apart:
///
/// * **Centred and scaled** ([_correlation]), which makes the score invariant to
///   `pixel = gain * reference + offset` — exactly the exposure and contrast
///   drift of a 1960s print against a modern photograph.
/// * **Tone-flattened** ([_equalise]), which additionally makes it invariant to
///   any *monotonic* tone curve. Fading, gamma and film response are not
///   affine, so they survive centring and scaling; spreading the histogram
///   evenly first removes them.
///
/// The score is the mean of the plain and the tone-flattened correlation,
/// floored at zero and capped at one. It is deliberately **not** stretched
/// across its range: it is reported as the raw correlation, so a genuine match
/// and an unrelated pair can be read off the real numbers instead of two
/// numbers invented to look well spread. Choosing where to put a
/// "is this a match" threshold needs a corpus of reviewed records; see the
/// note below.
///
/// ## What is not settled
///
/// Three labelled same-street pairs are available so far. Scored on the
/// production crop path, two of them separate clearly from a deliberately hard
/// negative set — unrelated photographs that are frequently of the *same
/// subject*, so near-misses are the common case rather than the exception:
///
/// | pair                                    | score | vs unrelated pairs             |
/// |-----------------------------------------|-------|--------------------------------|
/// | B&W 1961 vs modern photo                | 0.71  | above the 95th percentile       |
/// | painting vs modern photo                | 0.53  | between the 90th and 95th       |
/// | B&W 1961 vs modern photo (weak framing) | 0.23  | beaten by 32%                  |
///
/// The negative set has a median of 0.12, a 75th percentile of 0.28 and a 90th
/// percentile of 0.48.
///
/// The third pair is the open problem, and it is *not* a registration
/// problem: sweeping scale and offset corrections around the recorded viewport
/// only moved it from 0.23 to 0.27, so the shortfall is in the content the
/// metric sees, not in where the crop is taken. Its archival scan is also
/// visibly softer than the other two.
///
/// So discrimination is demonstrated for two of the three and **not** for the
/// third.
///
/// No threshold is applied on top of this: the score is reported as it falls
/// out of the correlation. For anyone reading a percentage off the comparison
/// page, the useful reference points are that set's median of 0.12 and its 90th
/// percentile of 0.48, so an unrelated pair usually lands in the teens and
/// anything past roughly 50% is unusual for two different places.
///
/// ## Cross-platform agreement
///
/// Both backends reduce to an integer [fingerprintSize] x [fingerprintSize] sRGB
/// block and then run *this* code, in Dart, on it. So the descriptor, the
/// equalisation and the correlation are bit-identical everywhere by
/// construction. All that is left to disagree is the downscale — the exact
/// area filter native uses versus the browser's `drawImage` — which can move a
/// channel by about one part in 255. A continuous metric absorbs that; the
/// median hash it replaced turned it into a 31% score swing.
///
/// ## Verified properties
///
/// Measured against the shipped pipeline, on real photographs:
///
/// * a picture compared with itself: `1.000`
/// * a global brightness or contrast change: `0.98` and above
/// * JPEG recompression at quality 40: `1.000`
/// * a 5% change of viewpoint: `0.74` to `0.92`
/// * a 20% change of viewpoint: `0.46` to `0.86`
///
/// Note how the last two compare with the `0.03`-`0.06` that different content
/// produces: viewpoint drift degrades the score gradually, and different
/// content collapses it.
class StructuralFingerprint implements PictureFingerprint {
  const StructuralFingerprint._(
    this._plain,
    this._flat,
    this._plainNorm,
    this._flatNorm,
  );

  /// Builds a fingerprint from a [fingerprintSize] x [fingerprintSize] block of
  /// sRGB — [fingerprintSamples] * 3 bytes, row-major — as produced by both
  /// backends.
  ///
  /// This is the seam: a different fingerprint type is returned here, and
  /// nothing else in the app needs to change.
  factory StructuralFingerprint.fromRgbBlock(Uint8List rgb) {
    assert(rgb.length == fingerprintSamples * 3,
        'Expected ${fingerprintSamples * 3} RGB bytes, got ${rgb.length}');
    final plain = Float64List(fingerprintSamples);
    for (var i = 0; i < fingerprintSamples; i++) {
      final offset = i * 3;
      plain[i] = luminance(rgb[offset], rgb[offset + 1], rgb[offset + 2]);
    }
    // Equalising is order-preserving, and centring is a monotone shift, so the
    // two orders commute and `_equalise(plain)` is equalised-then-centred.
    final flat = Float64List.fromList(_equalise(plain));
    return StructuralFingerprint._(
      plain,
      flat,
      _centre(plain),
      _centre(flat),
    );
  }

  /// Both blocks, each with its own mean subtracted, so that a similarity is a
  /// plain dot product of two centred vectors. Centring once here rather than
  /// inside [_correlation] keeps that function to a single pass, and makes the
  /// mean-removal impossible to forget.
  final Float64List _plain;
  final Float64List _flat;
  final double _plainNorm;
  final double _flatNorm;

  @override
  double similarityTo(PictureFingerprint other) {
    if (other is! StructuralFingerprint) {
      throw ArgumentError.value(other, 'other',
          'cannot be compared with a StructuralFingerprint');
    }
    final plain = _correlation(_plain, other._plain, _plainNorm, other._plainNorm);
    final flat = _correlation(_flat, other._flat, _flatNorm, other._flatNorm);
    // A negative correlation means the light and dark are arranged *oppositely*
    // — anti-correlated, which is as dissimilar as this metric can express, so
    // it is floored at zero rather than allowed to go negative.
    final blended = (1 - _toneFlattenedWeight) * max(0.0, plain) +
        _toneFlattenedWeight * max(0.0, flat);
    return blended.clamp(0.0, 1.0);
  }

  /// Luminance of an sRGB triple.
  ///
  /// Luminance is linear in RGB and so is an area filter, so averaging RGB and
  /// then taking luminance is the same as taking luminance and then averaging —
  /// which is what lets the browser average in RGB inside `drawImage` while
  /// native averages in RGB too, and both still land on the same block.
  static double luminance(int r, int g, int b) => 0.299 * r + 0.587 * g + 0.114 * b;

  /// Pearson correlation of two mean-centred blocks, given each one's norm.
  ///
  /// Returns 0 when either block carries no variation at all. A crop of flat
  /// sky, or of a blank wall, has no structure to correlate, and letting the
  /// arithmetic produce a number there is how a metric ends up claiming that two
  /// unrelated pictures are identical.
  static double _correlation(
    Float64List a,
    Float64List b,
    double aNorm,
    double bNorm,
  ) {
    if (aNorm < _degeneracyFloor || bNorm < _degeneracyFloor) {
      return 0.0;
    }
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum / (aNorm * bNorm);
  }

  /// Subtracts [values]' mean in place and returns the norm of the result.
  static double _centre(Float64List values) {
    var mean = 0.0;
    for (var i = 0; i < values.length; i++) {
      mean += values[i];
    }
    mean /= values.length;
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      final centred = values[i] - mean;
      values[i] = centred;
      sum += centred * centred;
    }
    return sqrt(sum);
  }

  /// Spreads [values] evenly over `0..255` by rank.
  ///
  /// Rank rather than histogram binning, so the transform is a pure
  /// re-ordering: two pictures with identical tone *distributions* map to
  /// identical blocks no matter what the absolute levels were. Equal values
  /// share the midpoint of the run they occupy, which keeps a flat region flat
  /// instead of amplifying its noise into a ramp.
  static Float64List _equalise(Float64List values) {
    final order = List<int>.generate(values.length, (i) => i)
      ..sort((a, b) => values[a].compareTo(values[b]));
    final out = Float64List(values.length);
    final top = values.length - 1;
    var runStart = 0;
    while (runStart < order.length) {
      var runEnd = runStart;
      while (runEnd + 1 < order.length &&
          values[order[runEnd + 1]] == values[order[runStart]]) {
        runEnd++;
      }
      // Midpoint of the run, so a block of equal values maps to one value.
      final level = top == 0 ? 0.0 : (runStart + runEnd) / 2 / top * 255;
      for (var i = runStart; i <= runEnd; i++) {
        out[order[i]] = level;
      }
      runStart = runEnd + 1;
    }
    return out;
  }
}

/// How much of the score comes from the tone-flattened correlation. The rest
/// comes from the plain one; see the class docs for why it is not all-or-nothing.
const double _toneFlattenedWeight = 0.5;

/// Below this norm-about-mean a block is treated as carrying no information.
const double _degeneracyFloor = 1e-6;

/// Scales the intersection of the two viewports onto a source image of
/// [width] x [height], or `null` when the crop is degenerate.
///
/// The source dimensions are only known once the image has been decoded, so
/// this necessarily runs inside a backend, not in the caller.
SimilarityCrop? resolveSimilarityCrop({
  required int width,
  required int height,
  required Rectangle<num> viewPort,
  required Rectangle<num> intersection,
}) {
  final rect = cropImage(
    width: width,
    height: height,
    viewPort: viewPort,
    intersection: intersection,
  );
  final crop = SimilarityCrop(rect.left, rect.top, rect.width, rect.height);
  if (crop.width <= 0 ||
      crop.height <= 0 ||
      crop.left >= width ||
      crop.top >= height) {
    return null;
  }
  return crop;
}
