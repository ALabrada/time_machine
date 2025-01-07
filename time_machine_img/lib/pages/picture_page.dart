import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_img/controllers/picture_controller.dart';
import 'package:time_machine_net/services/network_service.dart';

class PicturePage extends StatefulWidget {
  const PicturePage({
    super.key,
    this.pictureId,
  });

  final int? pictureId;

  @override
  _PicturePageState createState() => _PicturePageState();
}

class _PicturePageState extends State<PicturePage> with SingleTickerProviderStateMixin {
  late PictureController pictureController;
  late AnimationController animationController;

  @override
  void initState() {
    animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    pictureController = PictureController(
      databaseService: context.read(),
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: pictureController.loadPicture(widget.pictureId),
      builder: (context, snapshot) {
        final picture = snapshot.data;
        return Scaffold(
          // appBar: _buildAppBar(picture: picture),
          // extendBodyBehindAppBar: true,
          body: _buildContent(picture: picture),
        );
      },
    );
  }

  AppBar _buildAppBar({Picture? picture}) {
    return AppBar(
      title: ExtendedText(picture?.text ?? '',
        maxLines: 1,
        overflowWidget: TextOverflowWidget(
          position: TextOverflowPosition.middle,
          child: Text(
            "...",
          ),
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.secondary.withAlpha(127),
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent({Picture? picture}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (picture != null)
          GestureDetector(
            onTap: () async {
              if (animationController.value == 0) {
                await animationController.animateTo(1, curve: Curves.easeIn);
              } else {
                await animationController.animateBack(0, curve: Curves.easeIn);
              }
            },
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(picture.url),
              scaleStateChangedCallback: (state) async {
                if (animationController.value == 0.0 && state == PhotoViewScaleState.zoomedIn) {
                  await animationController.animateTo(1, curve: Curves.easeIn);
                } else if (animationController.value == 1.0 && state == PhotoViewScaleState.zoomedOut) {
                  await animationController.animateBack(0, curve: Curves.easeIn);
                }
              },
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: animationController,
            child: _buildAppBar(picture: picture),
            builder: (context, child) {
              return Opacity(
                opacity: 1 - animationController.value,
                child: Transform.translate(
                  offset: Offset(0, -MediaQuery.of(context).padding.top * animationController.value),
                  child: child,
                ),
              );
            },
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildToolbar(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return AnimatedBuilder(
      animation: animationController,
      child: SafeArea(
        child: Container(
          color: Theme.of(context).colorScheme.secondary.withAlpha(127),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: widget.pictureId == null ? null : _takePicture,
                  icon: Icon(Icons.camera_alt),
                ),
                IconButton(
                  onPressed: widget.pictureId == null ? null : () {
                    unawaited(pictureController.sharePicture());
                  },
                  icon: Icon(Icons.share),
                ),
              ],
            ),
          ),
        ),
      ),
      builder: (context, child) {
        return Opacity(
          opacity: 1 - animationController.value,
          child: Transform.translate(
            offset: Offset(0, 50 * animationController.value),
            child: child,
          ),
        );
      },
    );
  }

  void _takePicture() {
    context.go('/camera?pictureId=${widget.pictureId}');
  }
}
