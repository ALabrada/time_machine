import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_db/time_machine_db.dart';

class PictureView extends StatelessWidget {
  const PictureView({
    super.key,
    this.title,
    this.time,
    this.image,
    this.onLongPress,
    this.onTap,
    this.onTapImage,
  });

  PictureView.model({
    Key? key,
    Picture? model,
    VoidCallback? onLongPress,
    VoidCallback? onTap,
    VoidCallback? onTapImage,
  }) : this(
    key: key,
    time: model?.time,
    title: model?.description,
    image: model == null ? null : CachedNetworkImageProvider(model.previewUrl ?? model.url),
    onLongPress: onLongPress,
    onTap: onTap,
    onTapImage: onTapImage,
  );

  final String? title;
  final String? time;
  final ImageProvider? image;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onTapImage;

  @override
  Widget build(BuildContext context) {
    final text = _buildText(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsets.all(8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(context),
            if (text != null)
              ...[
                SizedBox(width: 8),
                Expanded(child: text),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final image = this.image;
    return InkWell(
      onTap: onTapImage,
      child: image == null ? Icon(Icons.question_mark,
        size: 48,
      ) : Image(
        image: image,
        height: 48,
        width: 48,
        fit: BoxFit.fitHeight,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return Container(
            alignment: Alignment.center,
            width: 48,
            height: 48,
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }

  Widget? _buildText(BuildContext context) {
    final title = this.title;
    final time = this.time;
    if ((title?.isEmpty ?? true) && (time?.isEmpty ?? true)) {
      return null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty)
          Text(title,
            maxLines: 2,
            style: TextTheme.of(context).bodyMedium,
          ),
        if (time != null && time.isNotEmpty)
          Text(time,
            style: TextTheme.of(context).bodySmall,
          ),
      ],
    );
  }
}
