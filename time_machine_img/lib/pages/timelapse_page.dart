import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gif/gif.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_img/controllers/playback_controller.dart';
import 'package:time_machine_img/controllers/timelapse_controller.dart';
import 'package:time_machine_img/domain/timelapse_state.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/frame_view.dart';
import 'package:time_machine_img/molecules/playback_tool_bar.dart';
import 'package:time_machine_res/time_machine_res.dart';

class TimelapsePage extends StatefulWidget {
  const TimelapsePage({
    super.key,
    this.recordId,
  });

  final int? recordId;

  @override
  TimelapsePageState createState() => TimelapsePageState();
}

class TimelapsePageState extends State<TimelapsePage>
    with SingleTickerProviderStateMixin {
  static const duration = Duration(seconds: 3);

  late PlaybackController playbackController;
  late TimelapseController controller;

  @override
  void initState() {
    playbackController = PlaybackController(
      vsync: this,
      baseDuration: duration,
    );
    controller = TimelapseController(
      cacheService: context.read(),
      databaseService: context.read(),
      duration: duration,
      playbackController: playbackController,
    );
    super.initState();
    unawaited(controller.loadRecord(widget.recordId));
  }

  @override
  void dispose() {
    playbackController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TimelapseState>(
      valueListenable: controller,
      builder: (context, state, _) {
        return Scaffold(
          appBar: _buildAppBar(),
          body: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            child: _buildContent(state),
          ),
          bottomNavigationBar: state is FinishedState
              ? PlaybackToolBar(
                  playbackController: playbackController,
                  controller: controller,
                )
              : null,
        );
      },
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(ImgLocalizations.of(context).timelapsePage),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
    );
  }

  Widget _buildContent(TimelapseState state) {
    if (state is FailedState) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.error.toString(),
              style: h3Style(context),
            ),
            SizedBox(height: 8),
            Text(
              state.stackTrace.toString(),
              style: bodyStyle(context),
            )
          ],
        ),
      );
    } else if (state is DownloadingState) {
      final percent = (state.progress * 100).toStringAsFixed(1);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: state.progress),
            SizedBox(height: 16),
            Text(
              ImgLocalizations.of(context).timelapseDownloading,
              style: h3Style(context),
            ),
            Text(
              "$percent%",
              style: bodyStyle(context),
            ),
          ],
        ),
      );
    } else if (state is RenderingState) {
      final showPreview = state.frame != null &&
          state.frameIndex != null &&
          state.totalFrames != null;
      final percent = (state.progress * 100).toStringAsFixed(1);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: state.progress),
            SizedBox(height: 16),
            Text(
              ImgLocalizations.of(context).timelapseRendering,
              style: h3Style(context),
            ),
            Text(
              "$percent%",
              style: bodyStyle(context),
            ),
            if (showPreview) ...[
              SizedBox(height: 24),
              FrameView(
                frame: state.frame!,
                frameIndex: state.frameIndex!,
                totalFrames: state.totalFrames!,
              ),
            ],
          ],
        ),
      );
    } else if (state is FinishedState) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Gif(
            image: MemoryImage(state.data),
            duration: controller.duration,
            controller: playbackController,
            onFetchCompleted: () {
              playbackController.play();
            },
          ),
        ),
      );
    } else {
      return LoadingView();
    }
  }
}
