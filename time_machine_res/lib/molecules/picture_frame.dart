import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_db/time_machine_db.dart';

class PictureFrame extends StatelessWidget {
  const PictureFrame({
    super.key,
    this.aspectRatio,
    this.margin,
    required this.child,
  });

  PictureFrame.model(Picture model, {
    Key? key,
    Widget? child,
  }) : this(
    key: key,
    margin: parseMargin(model.margin),
    child: child ?? Image(
      image: imageFor(model.url),
    ),
  );

  final double? aspectRatio;
  final EdgeInsets? margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = this.aspectRatio;
    final content = Stack(
      children: [
        Positioned(
          left: margin?.left ?? 0,
          top: margin?.top ?? 0,
          right: margin?.right ?? 0,
          bottom: margin?.bottom ?? 0,
          child: FittedBox(
            fit: BoxFit.contain,
            child: child,
          ),
        ),
      ],
    );
    return aspectRatio == null ? content : AspectRatio(
      aspectRatio: aspectRatio,
      child: content,
    );
  }

  static ImageProvider imageFor(String url) {
    final uri = Uri.parse(url);
    if (uri.isScheme('file')) {
      return FileImage(File(uri.path));
    }
    if (uri.isScheme('data')) {
      final data = base64Decode(url.split(';base64,').last);
      return MemoryImage(data);
    }
    return CachedNetworkImageProvider(url);
  }

  static EdgeInsets? parseMargin(String? margin) {
    if (margin == null) {
      return null;
    }
    final values = margin
        .split(RegExp(r'[\s,;]'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    print('Margin: $values');
    switch (values.length) {
      case 1: return EdgeInsets.all(values[0]);
      case 2: return EdgeInsets.symmetric(horizontal: values[0], vertical: values[1]);
      case 4: return EdgeInsets.fromLTRB(values[0], values[1], values[2], values[3]);
      default: return null;
    }
  }
}
