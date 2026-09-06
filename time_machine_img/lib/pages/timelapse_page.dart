import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gif/gif.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_img/controllers/playback_controller.dart';
import 'package:time_machine_img/controllers/timelapse_controller.dart';
import 'package:time_machine_img/domain/timelapse_state.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
import 'package:time_machine_img/molecules/frame_view.dart';
import 'package:time_machine_img/molecules/full_screen_view.dart';
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
    with TickerProviderStateMixin {
  static const duration = Duration(seconds: 2);
  static const _playbackToolbarHeight = 120.0;

  late PlaybackController playbackController;
  late TimelapseController controller;
  late AnimationController animationController;

  @override
  void initState() {
    animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    playbackController = PlaybackController(
      vsync: this,
      baseDuration: duration,
    );
    controller = TimelapseController(
      cacheService: context.read(),
      databaseService: context.read(),
      configurationService: context.read<ConfigurationService>(),
      duration: duration,
      playbackController: playbackController,
    );
    super.initState();
    unawaited(controller.loadRecord(widget.recordId));
  }

  @override
  void dispose() {
    animationController.dispose();
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
          body: FullScreenView(
            collapsible: state is FinishedState,
            animationController: animationController,
            topBar: _buildAppBar(),
            bottomBar: PreferredSize(
              preferredSize: const Size.fromHeight(_playbackToolbarHeight),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: state is FinishedState
                    ? PlaybackToolBar(
                        playbackController: playbackController,
                        controller: controller,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('no-playback-toolbar'),
                      ),
              ),
            ),
            content: AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: _buildContent(state),
            ),
          ),
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
        key: ValueKey('failed'),
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
        key: ValueKey('downloading'),
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
        key: ValueKey('rendering'),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
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
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                  child: FrameView(
                    frame: state.frame!,
                    frameIndex: state.frameIndex!,
                    totalFrames: state.totalFrames!,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } else if (state is FinishedState) {
      return SizedBox.expand(
        key: ValueKey('finished'),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Gif(
            image: MemoryImage(state.data),
            duration: controller.duration,
            controller: playbackController,
            placeholder: state.previewFrame == null
                ? null
                : (context) =>
                    Image.memory(state.previewFrame!, fit: BoxFit.contain),
            onFetchCompleted: () {
              playbackController.play();
            },
          ),
        ),
      );
    } else {
      return LoadingView(key: ValueKey('uninitialized'));
    }
  }
}
