export 'l10n/img_localizations.dart';
export 'pages/comparison_page.dart';
export 'pages/gallery_page.dart';
export 'pages/picture_page.dart';
export 'pages/timelapse_page.dart';
export 'pages/upload_page.dart';
export 'services/sharing_service.dart';

import 'dart:math';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:time_machine_db/time_machine_db.dart';

Future<img.Image?> cropImageFile({
  required XFile file,
  Rectangle<num>? viewPort,
  Rectangle<num>? intersection,
}) async {
  var originalImage = kIsWeb
      ? img.decodeImage(await file.readAsBytes())
      : await img.decodeImageFile(file.path);
  if (originalImage == null || intersection == null || viewPort == null) {
    return null;
  }
  final rect = cropImage(
    width: originalImage.width,
    height: originalImage.height,
    viewPort: viewPort,
    intersection: intersection,
  );
  return img.copyCrop(originalImage,
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
  );
}