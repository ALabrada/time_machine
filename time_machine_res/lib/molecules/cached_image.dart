import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:network_image_plus/html/network_image_html.dart';

class CachedImage extends StatelessWidget {
  const CachedImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
  });

  final String imageUrl;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return NetworkImagePlus(
        url: imageUrl,
        height: height,
        width: width,
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      height: height,
      width: width,
    );
  }
}
