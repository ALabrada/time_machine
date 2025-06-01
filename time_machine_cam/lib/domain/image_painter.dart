import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ImagePainter extends CustomPainter {
  final ui.Image? image;
  final double imageOpacity;
  final Path path;

  ImagePainter({
    required this.path,
    this.image,
    this.imageOpacity=1.0,
  });

  static CustomPaint create({
    required Path path,
    ui.Image? image,
    double imageOpacity=1.0,
  }) {
    return CustomPaint(
      painter: ImagePainter(
        image: image,
        imageOpacity: imageOpacity,
        path: path,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = path.getBounds();

    final image = this.image;
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image,
        fit: BoxFit.fill,
        opacity: imageOpacity,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImagePainter oldClipper) =>
      oldClipper.image != image || oldClipper.path != path;
}