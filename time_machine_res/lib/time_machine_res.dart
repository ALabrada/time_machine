import 'dart:math';

export 'atoms/buttons.dart';
export 'atoms/inputs.dart';
export 'atoms/labels.dart';
export 'atoms/themes.dart';
export 'controllers/task_manager.dart';
export 'molecules/fixed_orientation_view.dart';
export 'molecules/loading_container.dart';
export 'molecules/picture_frame.dart';
export 'molecules/picture_view.dart';
export 'tokens/colors.dart';
export 'tokens/typography.dart';

(double x, double y, double w, double h) aspectFitRect({
  required double width,
  required double height,
  required double innerWidth,
  required double innerHeight,
  double left=0,
  double top=0,
}) {
  final scale = min(width / innerWidth, height / innerHeight);
  final scaledWidth = innerWidth * scale;
  final scaledHeight = innerHeight * scale;
  final left = (width - scaledWidth) / 2.0;
  final top = (height - scaledHeight) / 2.0;
  return (left, top, scaledWidth, scaledHeight);
}

(double x, double y, double w, double h) fitRect({
  required double width,
  required double height,
  required double aspectRatio,
  double left=0,
  double top=0,
}) => aspectFitRect(
  width: width,
  height: height,
  innerWidth: aspectRatio,
  innerHeight: 1.0,
  left: left,
  top: top,
);