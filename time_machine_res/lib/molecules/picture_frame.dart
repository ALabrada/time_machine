import 'package:flutter/material.dart';
import 'package:time_machine_res/time_machine_res.dart';

class PictureFrame extends StatelessWidget {
  const PictureFrame({
    super.key,
    this.aspectRatio,
    this.margin,
    required this.child,
  });

  final double? aspectRatio;
  final EdgeInsets? margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = this.aspectRatio;
    if (aspectRatio == null) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final (l, t, w, h) = fitRect(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          aspectRatio: aspectRatio
        );
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: child,
          ),
        );
      },
    );
  }
}
