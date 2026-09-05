import 'package:flutter/material.dart';
import 'package:time_machine_img/controllers/playback_controller.dart';
import 'package:time_machine_img/controllers/timelapse_controller.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';

import 'settings_button.dart';
import 'tool_bar.dart';

class PlaybackToolBar extends StatelessWidget {
  const PlaybackToolBar({
    super.key,
    required this.playbackController,
    required this.controller,
  });

  static const _trackbarHeight = 24.0;

  final PlaybackController playbackController;
  final TimelapseController controller;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSecondary = Theme.of(context).colorScheme.onSecondary;
    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: _trackbarHeight / 2),
            ToolBar(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                IconButton(
                  tooltip: ImgLocalizations.of(context).timelapseShare,
                  onPressed: () => controller.shareGif(),
                  icon: const Icon(Icons.share),
                ),
                AnimatedBuilder(
                  animation: playbackController,
                  builder: (context, _) {
                    return IconButton(
                      onPressed: playbackController.togglePlayback,
                      icon: Icon(
                        playbackController.isAnimating
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    );
                  },
                ),
                SettingsButton(
                  playbackController: playbackController,
                  controller: controller,
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: _trackbarHeight,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: primary,
                inactiveTrackColor: onSecondary.withValues(alpha: 0.3),
                thumbColor: primary,
                overlayColor: primary.withValues(alpha: 0.2),
                trackHeight: 2,
                padding: EdgeInsets.zero,
              ),
              child: AnimatedBuilder(
                animation: playbackController,
                builder: (context, _) {
                  return Slider(
                    value: playbackController.value,
                    onChanged: (value) {
                      playbackController.value = value;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}