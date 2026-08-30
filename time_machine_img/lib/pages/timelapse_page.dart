import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_img/controllers/comparison_controller.dart';
import 'package:time_machine_img/controllers/timelapse_controller.dart';
import 'package:time_machine_img/domain/timelapse_state.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';
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

  late AnimationController animationController;
  late TimelapseController controller;

  @override
  void initState() {
    animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4),
    )..repeat(reverse: true);
    controller = TimelapseController(
      cacheService: context.read(),
      databaseService: context.read(),
    );
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    animationController.stop();
    await controller.loadRecord(widget.recordId);
    animationController.repeat(min: 0, reverse: true);
  }

  @override
  void dispose() {
    animationController.dispose();
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
          body: _buildContent(state),
          bottomNavigationBar: state is FinishedState ? PlaybackToolBar(
            animationController: animationController,
          ) : null,
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
            Text(state.error.toString(), style: h3Style(context),),
            SizedBox(height: 8),
            Text(state.stackTrace.toString(), style: bodyStyle(context),)
          ],
        ),
      );
    } else if (state is DownloadingState) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: state.progress),
            SizedBox(height: 8),
            Text("Downloading...", style: bodyStyle(context),),
          ],
        ),
      );
    } else if (state is RenderingState) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: state.progress),
            SizedBox(height: 8),
            Text("Rendering...", style: bodyStyle(context),),
          ],
        ),
      );
    } else if (state is FinishedState) {
      return Image.memory(state.data);
    } else {
      return LoadingView();
    }
  }
}