import 'dart:async';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_compare_slider/image_compare_slider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_img/controllers/comparison_controller.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/comparison_description.dart';
import 'package:time_machine_img/molecules/full_screen_view.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../controllers/upload_controller.dart';
import '../molecules/tool_bar.dart';

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({
    super.key,
    this.recordId,
  });

  final int? recordId;

  @override
  _ComparisonPageState createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> with SingleTickerProviderStateMixin {
  static const defaultAspectRatio = 4.0/3.0;

  late ComparisonController comparisonController;
  late AnimationController animationController;

  final ValueNotifier<SliderDirection> sliderDirection = ValueNotifier(SliderDirection.leftToRight);

  @override
  void initState() {
    animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    comparisonController = ComparisonController(
      cacheManager: CachedNetworkImageProvider.defaultCacheManager,
      databaseService: context.read(),
      networkService: context.read(),
      telegramService: context.read(),
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: comparisonController.loadRecord(widget.recordId),
      builder: (context, snapshot) {
        final record = snapshot.data;
        return Scaffold(
          appBar: _buildAppBar(),
          body: FutureBuilder(
            future: comparisonController.comparePictures(record).onError((e, _) {
              print("comparePictures error: $e");
            }),
            builder: (context, snapshot) {
              return _buildContent(record: record, match: snapshot.data);
            },
          ),
          bottomNavigationBar: _buildToolbar(),
        );
      },
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(ImgLocalizations.of(context).comparisonPage),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget? _buildComparison({Record? record, SliderDirection? direction}) {
    final aspectRatio = record?.aspectRatio ?? defaultAspectRatio;
    final picture = record?.picture;
    final original = record?.original;
    if (picture == null || original == null) {
      return null;
    }
    return ImageCompareSlider(
      itemOne: Image(image: PictureFrame.imageFor(original.url)),
      itemTwo: Image(image: PictureFrame.imageFor(picture.url)),
      itemOneBuilder: (child, context) => PictureFrame(
        aspectRatio: aspectRatio,
        child: child,
      ),
      itemTwoBuilder: (child, context) => PictureFrame(
        aspectRatio: aspectRatio,
        child: child,
      ),
      handleColor: Theme.of(context).colorScheme.primary,
      dividerColor: Theme.of(context).colorScheme.primary,
      fillHandle: true,
      direction: direction ?? sliderDirection.value,
    );
  }

  Widget _buildContent({Record? record, double? match}) {
    return ValueListenableBuilder(
      valueListenable: sliderDirection,
      builder: (context, direction, _) {
        final comparison = _buildComparison(
          record: record,
          direction: direction,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (comparison != null)
                  comparison,
                Positioned(
                  left: 0,
                  bottom: 0,
                  right: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: constraints.maxHeight / 3),
                    child: SingleChildScrollView(
                      child: ComparisonDescription(
                        firstPicture: record?.original,
                        secondPicture: record?.picture,
                        match: match,
                        direction: direction,
                        onTapFirstPicture: () => showPicture(record?.original),
                        onTapSecondPicture: () => showPicture(record?.picture),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildToolbar() {
    return StreamBuilder(
      stream: comparisonController.isProcessing,
      initialData: false,
      builder: (context, snapshot) {
        return ToolBar(
          children: [
            IconButton(
              onPressed: _rotateClockwise,
              icon: Icon(Icons.rotate_right),
            ),
            IconButton(
              onPressed: openMap,
              icon: Icon(Icons.location_pin),
            ),
            if (snapshot.requireData)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              )
            else IconButton(
              onPressed: widget.recordId == null ? null : () {
                unawaited(showSharingMenu());
              },
              icon: Icon(Icons.share),
            ),
            IconButton(
              onPressed: widget.recordId == null ? null : () {
                unawaited(delete());
              },
              icon: Icon(Icons.delete),
            ),
          ],
        );
      },
    );
  }

  void _rotateClockwise() {
    switch (sliderDirection.value) {
      case SliderDirection.leftToRight:
        sliderDirection.value = SliderDirection.topToBottom;
      case SliderDirection.topToBottom:
        sliderDirection.value = SliderDirection.rightToLeft;
      case SliderDirection.rightToLeft:
        sliderDirection.value = SliderDirection.bottomToTop;
      default:
        sliderDirection.value = SliderDirection.leftToRight;
    }
  }
  
  Future<void> delete() async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context, 
      builder: (context) {
        return SimpleDialog(
          title: Text(ImgLocalizations.of(context).deleteOneSubtitle),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(ImgLocalizations.of(context).deleteConfirm,
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(ImgLocalizations.of(context).deleteCancel),
            ),
          ],
        );
      },
    );
    if (confirm != true) {
      return;
    }

    if (await comparisonController.removeRecord() && mounted) {
      Navigator.of(context).pop();
    }
  }

  void showPicture(Picture? element) {
    if (element == null) {
      return;
    }
    context.go('/gallery/${widget.recordId}/picture/${element.localId}');
  }

  void openMap() {
    final pictureId = comparisonController.record?.originalId;
    if (pictureId == null) {
      return;
    }
    context.go('/?tab=map&pictureId=$pictureId');
  }

  Future<void> publishToTelegram() async {
    if (!await comparisonController.publishToTelegram()) {
      return;
    }
    final channelName = comparisonController.telegramService?.channelName;
    if (channelName != null) {
      await launchUrlString('https://t.me/$channelName',
          mode: LaunchMode.externalNonBrowserApplication,
      );
    }
  }

  Future<void> showSharingMenu() async {
    await showAdaptiveActionSheet(
      context: context,
      title: Text( ImgLocalizations.of(context).shareMenu),
      cancelAction: CancelAction(title: Text(ImgLocalizations.of(context).shareMenuCancel)),
      actions: [
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).shareMenuPublishTo('re.photos')),
          onPressed: (context) {
            final originalPicture = comparisonController.record?.original;
            final page = originalPicture != null && originalPicture.provider == 're.photos' ?
                '${UploadController.defaultPageUrl}with_before/${originalPicture.id}/' :
                UploadController.defaultPageUrl;
            context.go('/gallery/${widget.recordId}/upload?webPage=${Uri.encodeQueryComponent(page)}');
            context.pop();
          },
        ),
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).shareMenuPublishTo('Telegram')),
          onPressed: (context) {
            unawaited(publishToTelegram());
            context.pop();
          },
        ),
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).shareMenuExport),
          onPressed: (context) {
            unawaited(comparisonController.exportRecord(
              dialogTitle: ImgLocalizations.of(context).shareMenuExport,
            ));
            context.pop();
          },
        ),
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).shareMenuImages),
          onPressed: (context) {
            unawaited(comparisonController.sharePictures());
            context.pop();
          },
        ),
      ],
    );
  }
}
