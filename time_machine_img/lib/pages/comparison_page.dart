import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_compare_slider/image_compare_slider.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_img/controllers/comparison_controller.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/full_screen_view.dart';
import 'package:time_machine_res/time_machine_res.dart';

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
      databaseService: context.read(),
      networkService: context.read(),
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
          body: _buildContent(record: record),
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
    final picture = record?.picture;
    final original = record?.original;
    if (picture == null || original == null) {
      return null;
    }
    return ImageCompareSlider(
      itemOne: Image(image: PictureFrame.imageFor(original.url)),
      itemTwo: Image(image: PictureFrame.imageFor(picture.url)),
      itemOneBuilder: (child, context) => PictureFrame(
        aspectRatio: 4.0/3.0,
        child: child,
      ),
      itemTwoBuilder: (child, context) => PictureFrame(
        aspectRatio: 4.0/3.0,
        child: child,
      ),
      handleColor: Theme.of(context).colorScheme.primary,
      dividerColor: Theme.of(context).colorScheme.primary,
      fillHandle: true,
      direction: direction ?? sliderDirection.value,
    );
  }

  Widget _buildContent({Record? record}) {
    return ValueListenableBuilder(
      valueListenable: sliderDirection,
      builder: (context, direction, _) {
        final comparison = _buildComparison(
          record: record,
          direction: direction,
        );
        final labels = _labelsFor(direction);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (comparison != null)
              comparison,
            Positioned(
              left: 0,
              bottom: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: background02.withAlpha(127),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: "${labels[0]}: ",
                        style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                          fontWeight: FontWeight.w600,
                        )),
                        children: [
                          TextSpan(
                            text: record?.original?.text ?? '',
                            style: TextTheme.of(context).bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: "${labels[1]}: ",
                        style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                          fontWeight: FontWeight.w600,
                        )),
                        children: [
                          TextSpan(
                            text: record?.picture?.text ?? '',
                            style: TextTheme.of(context).bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar() {
    return SafeArea(
      child: Container(
        color: Theme.of(context).colorScheme.secondary,
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
                onPressed: _rotateClockwise,
                icon: Icon(Icons.rotate_right),
              ),
              IconButton(
                onPressed: widget.recordId == null ? null : () {
                  unawaited(showSharingMenu());
                },
                icon: Icon(Icons.share),
              ),
              IconButton(
                onPressed: widget.recordId == null ? null : () async {
                  if (await comparisonController.removeRecord() && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(Icons.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _labelsFor(SliderDirection direction) {
    final loc = ImgLocalizations.of(context);
    switch (direction) {
      case SliderDirection.leftToRight:
        return [];
      case SliderDirection.topToBottom:
        return [loc.comparisonTop, loc.comparisonBottom];
      case SliderDirection.rightToLeft:
        return [loc.comparisonRight, loc.comparisonLeft];
      default:
        return [loc.comparisonBottom, loc.comparisonTop];
    }
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

  Future<void> showSharingMenu() async {
    await showAdaptiveActionSheet(
      context: context,
      title: Text( ImgLocalizations.of(context).shareMenu),
      cancelAction: CancelAction(title: Text(ImgLocalizations.of(context).shareMenuCancel)),
      actions: [
        BottomSheetAction(
          title: Text(ImgLocalizations.of(context).shareMenuUploadTo('re.photos')),
          onPressed: (context) {
            context.go('/gallery/${widget.recordId}/upload');
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
