import 'dart:math';

export 'domain/cloud_metadata.dart';
export 'domain/date_time_converter.dart';
export 'domain/location.dart';
export 'domain/picture.dart';
export 'domain/picture_mirror.dart';
export 'domain/record.dart';
export 'domain/record_mirror.dart';
export 'services/repository.dart';
export 'services/cloud_sync_provider.dart';
export 'services/cloud_sync_service.dart';
export 'services/database_service.dart';

const filePathPlaceholder = '/[FILES]';

Rectangle<int> cropImage({
  required int width,
  required int height,
  required Rectangle viewPort,
  required Rectangle intersection,
}) {
  final scaleX = width.toDouble() / viewPort.width;
  final scaleY = height.toDouble() / viewPort.height;

  final x = scaleX * max(0, intersection.left - viewPort.left);
  final y = scaleY * max(0, intersection.top - viewPort.top);
  final w = scaleX * intersection.width;
  final h = scaleY * intersection.height;
  return Rectangle<int>(x.toInt(), y.toInt(), w.toInt(), h.toInt());
}

String expandPathGlobal(String path, String? filePath) {
  if (filePath == null) {
    return path;
  }
  return Uri.decodeFull(path).replaceAll(filePathPlaceholder, filePath);
}