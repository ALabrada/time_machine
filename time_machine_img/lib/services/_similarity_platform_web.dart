import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picture_fingerprint.dart';
import 'similarity_dart_decode.dart';

/// Web backend: lets the browser decode and downscale, so nothing blocks.
///
/// There are no isolates on the web, but the work does not have to happen on
/// the UI thread for that to be fine — it has to happen *natively*, which the
/// browser is very good at:
///
/// 1. `createImageBitmap` decodes the JPEG asynchronously; the returned
///    [web.ImageBitmap] exposes the source dimensions, so the crop rectangle
///    can be computed without ever materializing pixels in Dart.
/// 2. One `drawImage` of that bitmap into a [fingerprintSize] x
///    [fingerprintSize] 2D canvas both crops and area-averages, in the engine's
///    own rasterizer. At a ~100x downscale every engine area-averages, which is
///    the filter the native backend implements exactly.
/// 3. `getImageData` hands Dart [fingerprintSamples] RGBA pixels. That is the
///    *only* image data the UI isolate ever sees — 4 KB instead of the tens of
///    megabytes a Dart decode of a full-resolution photograph would allocate.
///
/// From there the work is identical to native: the same sRGB block goes into
/// [StructuralFingerprint.fromRgbBlock], which is pure Dart.
///
/// `drawImage` is used in preference to `createImageBitmap`'s own
/// `resizeWidth`/`resizeQuality` options even though those would fold the
/// downscale into the decode: the resize *quality* levels are explicitly
/// implementation-defined in the HTML spec, whereas large-downscale
/// `drawImage` behaviour is consistent, and cross-platform agreement is worth
/// more here than one saved raster pass.
Future<PictureFingerprint?> computeSimilarityFingerprint({
  required Uint8List bytes,
  required Rectangle<num> viewPort,
  required Rectangle<num> intersection,
}) async {
  // A canvas composites with premultiplied alpha, so `getImageData` cannot
  // return the RGB of a partly- or fully-transparent pixel: it has already
  // been multiplied away. `package:image` on native just ignores alpha, so for
  // a container that can carry it the two platforms would be looking at
  // genuinely different pixels. JPEG cannot carry alpha, so this only diverts
  // the formats that need it.
  if (!_browserDecodesNatively || _mayCarryAlpha(bytes)) {
    // Preserve the previous behaviour on browsers we cannot hand the work to,
    // and stay correct for images the canvas cannot represent.
    return fingerprintWithDartDecoder(
      bytes: bytes,
      viewPort: viewPort,
      intersection: intersection,
    );
  }

  final bitmap = await web.window
      .createImageBitmap(
        web.Blob(
          <JSAny>[bytes.toJS].toJS,
          web.BlobPropertyBag(type: _mediaTypeOf(bytes)),
        ),
        // `from-image` is the default and would apply EXIF orientation.
        // `package:image` does not, so leaving it on would compare a rotated
        // picture on the web against an unrotated one natively — the two
        // platforms measuring different things. These files are stored
        // already-oriented (the camera app bakes orientation on capture), so
        // declining to rotate is what keeps the platforms in agreement.
        web.ImageBitmapOptions(imageOrientation: 'none'),
      )
      .toDart;
  try {
    final crop = resolveSimilarityCrop(
      width: bitmap.width,
      height: bitmap.height,
      viewPort: viewPort,
      intersection: intersection,
    );
    if (crop == null || crop.isSmallerThanGrid) {
      return null;
    }

    // A detached canvas: it is never added to the DOM and never composited, it
    // exists only to be read back. `willReadFrequently` keeps it in software,
    // which is what we want for a canvas whose sole purpose is one getImageData.
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = fingerprintSize
      ..height = fingerprintSize;
    final context = canvas.getContext(
      '2d',
      web.CanvasRenderingContext2DSettings(willReadFrequently: true),
    ) as web.CanvasRenderingContext2D?;
    if (context == null) {
      return null;
    }

    context.drawImage(
      bitmap,
      crop.left.toDouble(),
      crop.top.toDouble(),
      crop.width.toDouble(),
      crop.height.toDouble(),
      0,
      0,
      fingerprintSize.toDouble(),
      fingerprintSize.toDouble(),
    );

    // Unpremultiplied sRGB RGBA, row-major. Reaching here means the container
    // cannot carry alpha, so the alpha channel is uniformly opaque and there is
    // nothing to undo.
    final data = context
        .getImageData(0, 0, fingerprintSize, fingerprintSize)
        .data
        .toDart;
    final rgb = Uint8List(fingerprintSamples * 3);
    for (var i = 0; i < fingerprintSamples; i++) {
      final source = i * 4;
      final offset = i * 3;
      rgb[offset] = data[source];
      rgb[offset + 1] = data[source + 1];
      rgb[offset + 2] = data[source + 2];
    }
    return StructuralFingerprint.fromRgbBlock(rgb);
  } finally {
    bitmap.close();
  }
}

/// Whether the browser can decode a picture for us.
///
/// The gate deliberately mirrors Flutter's own
/// `browserSupportsCreateImageBitmap` (see the engine's
/// `lib/_engine/engine/dom.dart`), because the engine already relies on this
/// exact capability to decode images:
/// * the API itself is Baseline widely available (Chrome 50, Firefox 42,
///   Safari 15), so this only ever excludes genuinely old browsers;
/// * Chrome 110 and older are excluded because of a Chromium bug that renders
///   `createImageBitmap` output **vertically flipped**, which would silently
///   fingerprint a mirrored image and produce a wrong score rather than an error.
///
/// So the web build never raises its own minimum browser requirement above
/// what Flutter already demands.
bool get _browserDecodesNatively {
  if (!globalContext.has('createImageBitmap')) {
    return false;
  }
  final chromeVersion = RegExp(r'Chrom(?:e|ium)/(\d+)\.')
      .firstMatch(web.window.navigator.userAgent)
      ?.group(1);
  if (chromeVersion != null) {
    final version = int.tryParse(chromeVersion);
    if (version != null) {
      return version > 110;
    }
  }
  return true;
}

/// The MIME type to hand the [web.Blob].
///
/// The browser sniffs the real container regardless, so this is not a security
/// boundary — but labelling the bytes honestly is free, and a `Blob` claiming
/// `image/jpeg` while carrying PNG has no reason to be tolerated.
String _mediaTypeOf(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return 'image/avif';
  }
  return 'application/octet-stream';
}

/// Whether the encoded bytes are in a container that can carry an alpha
/// channel, and so cannot survive a round trip through a 2D canvas.
///
/// JPEG is the only common photographic container that cannot, which is why
/// this is not simply "is it not a JPEG": the cache holds whatever the device
/// camera or the network handed us.
bool _mayCarryAlpha(Uint8List bytes) {
  final type = _mediaTypeOf(bytes);
  return type != 'image/jpeg';
}
