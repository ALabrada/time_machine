import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_res/time_machine_res.dart';

class GalleryCell extends StatelessWidget {
  const GalleryCell({
    super.key,
    this.image,
    this.isSelected,
    this.onTap,
    this.onLongPress,
  });

  final ImageProvider? image;
  final bool? isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          alignment: Alignment.bottomRight,
          decoration: _buildDecoration(context),
          child: _buildCheckbox(context),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration(BuildContext context) {
    final image = this.image;
    return BoxDecoration(
      image: image == null ? null : DecorationImage(
        image: image,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget? _buildCheckbox(BuildContext context) {
    final isSelected = this.isSelected;
    if (isSelected == null) {
      return null;
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            offset: Offset(0,2),
            blurRadius: 10.0,
            color: gray06.withValues(alpha: 0.5),
          ),
        ],
      ),
      margin: EdgeInsets.all(4),
      child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
        size: 16,
        color: Theme.of(context).primaryColor,
      ),
    );
  }
}
