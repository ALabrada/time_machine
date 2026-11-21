import 'dart:typed_data';

import 'package:time_machine_core/domain/record.dart';

import '_similarity_platform.dart';

/// Similarity between a record's own picture and the historical picture it
/// replicates.
///
/// The score answers one question: **does this show the same place, from
/// roughly the same viewpoint, as the historical picture** — which is the
/// question the comparison page asks, and which holds up for photographs taken
/// decades apart despite changes of colour, exposure, film stock, print
/// fading and weather.
///
/// It is deliberately *not* a semantic or object-level similarity, and does not
/// try to be: nothing here knows what a building is, or that a bare tree once
/// had leaves. It measures the arrangement of light and dark across the shared
/// part of the two viewports. See [StructuralFingerprint] for the metric and for
/// the measurements behind it.
///
/// Everything above the [PictureFingerprint] interface is written against the
/// interface only, so a stronger metric — a learned embedding that understands
/// "these two show the same kind of thing" — can be introduced later without
/// touching the service, the controller or the page.
///
/// It is *not* an AI model today, and deliberately so. A fingerprint is a
/// thousand numbers compared with a dot product; the only expensive part of
/// producing it is decoding and downscaling the source photograph, and a model
/// would still need that decode on the calling thread. Worse, no inference
/// runtime gives you parallelism on the web — `flutter_litert`'s web backend is
/// tflite-js WASM on the main thread, and this project's own filM port had to
/// abandon it for exactly that reason (see `_litert_platform_web.dart`). The
/// work belongs on a background *thread*, and only the platform's own
/// primitives can put it there.
///
/// What the two backends actually do:
///
/// * **Native**: [Isolate.run] around a `package:image` decode, crop and
///   area-weighted downscale — the whole full-resolution pass chain stays off
///   the UI isolate.
/// * **Web**: `createImageBitmap` decodes without blocking, and a
///   [fingerprintSize] x [fingerprintSize] 2D canvas crops and area-averages
///   the result in the browser's own rasterizer. No full-resolution image is
///   ever materialized in Dart, and the main thread only ever touches 4 KB of
///   pixels.
///
/// Both produce the same sRGB block, so the score is comparable across
/// platforms to within a single 8-bit step — which a continuous metric absorbs.
class SimilarityService {
  const SimilarityService._();

  /// Similarity between [record]'s own picture and its original, in `[0, 1]`,
  /// or `null` when the pair cannot be compared — a missing or unparsable
  /// viewport, no overlap between the two viewports, an undecodable file, or a
  /// crop smaller than the fingerprint grid.
  ///
  /// [originalBytes] and [ownBytes] are the encoded files. Passing bytes
  /// rather than file handles is what lets the native backend cross an isolate
  /// boundary and the web backend hand a [Blob] to the browser decoder.
  static Future<double?> computeSimilarity({
    required Record record,
    required Uint8List originalBytes,
    required Uint8List ownBytes,
  }) async {
    final originalViewPort = Record.tryParseViewPort(record.originalViewPort);
    final pictureViewPort = Record.tryParseViewPort(record.pictureViewPort);
    if (originalViewPort == null || pictureViewPort == null) {
      return null;
    }

    // dart:math's Rectangle.intersection already returns null when the two
    // viewports do not overlap; a zero-area rectangle is also possible when
    // they merely touch, so reject that too.
    final intersection = originalViewPort.intersection(pictureViewPort);
    if (intersection == null ||
        intersection.width <= 0 ||
        intersection.height <= 0) {
      return null;
    }

    // Both fingerprints are independent, and both decodes are I/O- and
    // CPU-bound, so run them together: on the web both decodes are then in
    // flight at once.
    final fingerprints = await Future.wait([
      computeSimilarityFingerprint(
        bytes: originalBytes,
        viewPort: originalViewPort,
        intersection: intersection,
      ),
      computeSimilarityFingerprint(
        bytes: ownBytes,
        viewPort: pictureViewPort,
        intersection: intersection,
      ),
    ]);

    final originalFingerprint = fingerprints[0];
    final ownFingerprint = fingerprints[1];
    if (originalFingerprint == null || ownFingerprint == null) {
      return null;
    }
    return originalFingerprint.similarityTo(ownFingerprint);
  }
}
