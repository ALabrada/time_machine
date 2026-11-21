import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'picture_fingerprint.dart';
import 'similarity_dart_decode.dart';

/// Native backend: decodes and downscales on a background isolate.
///
/// The whole point is that a full-resolution photograph is never touched on
/// the UI isolate. `Isolate.run` gives us that for free as long as only
/// sendable values cross the boundary, so this function takes the encoded
/// [bytes] plus plain geometry and rebuilds the crop rectangle *inside* the
/// isolate — the source dimensions are only known after the decode.
Future<PictureFingerprint?> computeSimilarityFingerprint({
  required Uint8List bytes,
  required Rectangle<num> viewPort,
  required Rectangle<num> intersection,
}) {
  return Isolate.run(
    () => fingerprintWithDartDecoder(
      bytes: bytes,
      viewPort: viewPort,
      intersection: intersection,
    ),
  );
}
