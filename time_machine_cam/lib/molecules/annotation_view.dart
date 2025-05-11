import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_cam/domain/picture_annotation.dart';
import 'package:time_machine_cam/l10n/cam_localizations.dart';

class AnnotationView extends StatelessWidget {
  const AnnotationView({
    super.key,
    required this.annotation,
    this.onTap,
    this.onTapPicture,
  });

  final PictureAnnotation annotation;
  final VoidCallback? onTap;
  final VoidCallback? onTapPicture;

  @override
  Widget build(BuildContext context) {
    final title = annotation.picture.description ?? '';
    final time = annotation.picture.time ?? '';
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: Colors.white.withAlpha(127),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTapPicture,
                child: CachedNetworkImage(
                  imageUrl: annotation.picture.previewUrl ?? annotation.picture.url,
                  height: 40,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (time.isNotEmpty)
                      Text(
                        annotation.picture.time ?? '',
                      ),
                    Text(
                      CamLocalizations.of(context).distanceInMeters(annotation.distanceFromUser.toStringAsFixed(0)),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
