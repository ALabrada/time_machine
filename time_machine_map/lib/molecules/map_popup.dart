import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_net/time_machine_net.dart';

class MapPopup extends StatelessWidget {
  const MapPopup({
    super.key,
    this.model,
    this.onShowImage,
  });

  final Picture? model;
  final VoidCallback? onShowImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(context),
          SizedBox(width: 8),
          Expanded(child: _buildText(context)),
        ],
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final model = this.model;
    return InkWell(
      onTap: onShowImage,
      child: model == null ? Icon(Icons.question_mark,
        size: 48,
      ) : CachedNetworkImage(
        imageUrl: model.previewUrl ?? model.url,
        height: 48,
      ),
    );
  }

  Widget _buildText(BuildContext context) {
    final description = model?.description;
    final time = model?.time;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null && description.isNotEmpty)
          Text(description,
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
