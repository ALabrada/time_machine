/// Platform facade for the genuinely platform-specific part of
/// [SimilarityService]: turning an encoded picture into a
/// [PictureFingerprint].
///
/// The fingerprint itself is platform-agnostic and lives in
/// `picture_fingerprint.dart`; only the decode-and-downscale step differs,
/// because only the two platforms disagree about where a full-resolution
/// image may be materialized:
///
/// * native: an isolate exists, so a `package:image` decode + crop + area
///   downscale runs on a background thread and the UI isolate never sees a
///   full-resolution buffer;
/// * web: isolates do not exist, so the *browser* does the work —
///   `createImageBitmap` decodes off the calling path and the canvas
///   rasterizer crops and area-averages natively, leaving Dart to read a
///   [fingerprintSize] x [fingerprintSize] block. There is no model and no
///   inference runtime involved, because neither would move the decode off the
///   main thread.
///
/// Both hand the same sRGB block to the same Dart fingerprint code, so the
/// score does not depend on which platform produced it.
library;

export 'picture_fingerprint.dart'
    show PictureFingerprint, StructuralFingerprint, fingerprintSamples, fingerprintSize;

export '_similarity_platform_web.dart'
    if (dart.library.io) '_similarity_platform_io.dart'
    show computeSimilarityFingerprint;
