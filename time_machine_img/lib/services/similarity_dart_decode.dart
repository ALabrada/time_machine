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
  final crop = resolveSimilarityCrop(
    width: image.width,
    height: image.height,
    viewPort: viewPort,
    intersection: intersection,
  );
  if (crop == null || crop.isSmallerThanGrid) {
    return null;
  }

  final cropped = img.copyCrop(
    image,
    x: crop.left,
    y: crop.top,
    width: crop.width,
    height: crop.height,
  );

  // The crop is handed to the shared reducer as a plain RGB buffer so that
  // native and web run the identical area-average arithmetic — see
  // `areaAverageRgbBlock`. `getBytes` normalizes channel order and count in
  // one pass and drops any alpha, so no separate conversion pass is needed.
  return StructuralFingerprint.fromRgbBlock(
    areaAverageRgbBlock(
      cropped.getBytes(order: img.ChannelOrder.rgb),
      width: cropped.width,
      height: cropped.height,
    ),
  );
}

