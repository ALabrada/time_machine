import 'dart:math';

export 'domain/location.dart';
export 'domain/picture.dart';
export 'domain/record.dart';
export 'services/database_service.dart';

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
  final h = scaleX * intersection.height;
  return Rectangle<int>(x.toInt(), y.toInt(), w.toInt(), h.toInt());
}