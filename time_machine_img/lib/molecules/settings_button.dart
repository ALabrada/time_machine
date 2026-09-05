import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_img/controllers/playback_controller.dart';
import 'package:time_machine_img/controllers/timelapse_controller.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';

import 'quality_dialog.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.playbackController,
    required this.controller,
  });

  final PlaybackController playbackController;
  final TimelapseController controller;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return IconButton(
          tooltip: ImgLocalizations.of(context).timelapseSettings,
          icon: const Icon(Icons.settings),
          onPressed: () => _showSettingsSheet(context),
        );
      },
    );
  }

  void _showSettingsSheet(BuildContext context) {
    final l10n = ImgLocalizations.of(context);
    showAdaptiveActionSheet<String>(
      context: context,
      title: Text(l10n.timelapseSettings),
      cancelAction: CancelAction(title: Text(l10n.timelapseCancel)),
      actions: [
        BottomSheetAction(
          leading: const Icon(Icons.repeat),
          title: Text(l10n.timelapseAutoReplay),
          trailing: playbackController.autoReplay
              ? Icon(
                  Icons.check,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onPressed: (sheetContext) {
            Navigator.of(sheetContext).pop('autoReplay');
          },
        ),
        BottomSheetAction(
          leading: const Icon(Icons.speed),
          title: Text(l10n.timelapsePlaybackSpeed),
          trailing: Text(
            '${playbackController.playbackSpeed.toStringAsFixed(2)}x',
          ),
          onPressed: (sheetContext) {
            Navigator.of(sheetContext).pop('speed');
          },
        ),
        BottomSheetAction(
          leading: const Icon(Icons.high_quality),
          title: Text(l10n.timelapseQuality),
          trailing: Text(
            '${resolutionPClass(controller.frameSize)} · '
            '${l10n.timelapseFps(controller.fps)}',
          ),
          onPressed: (sheetContext) {
            Navigator.of(sheetContext).pop('quality');
          },
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) {
        return;
      }
      switch (value) {
        case 'autoReplay':
          playbackController.setAutoReplay(!playbackController.autoReplay);
          break;
        case 'speed':
          _showSpeedSheet(context);
          break;
        case 'quality':
          _showQualityDialog(context);
          break;
      }
    });
  }

  void _showSpeedSheet(BuildContext context) {
    showSliderSheet(
      context: context,
      title: ImgLocalizations.of(context).timelapsePlaybackSpeed,
      initial: playbackController.playbackSpeed,
      min: 0.25,
      max: 3.0,
      divisions: 11,
      label: (value) => '${value.toStringAsFixed(2)}x',
      onChanged: playbackController.setPlaybackSpeed,
    );
  }

  Future<void> _showQualityDialog(BuildContext context) async {
    final result = await showDialog<({int frameSize, int fps})>(
      context: context,
      builder: (dialogContext) => QualityDialog(
        frameSize: controller.frameSize,
        fps: controller.fps,
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    controller.setQuality(
      frameSize: result.frameSize,
      fps: result.fps,
    );
  }
}

void showSliderSheet({
  required BuildContext context,
  required String title,
  required double initial,
  required double min,
  required double max,
  required int divisions,
  required String Function(double) label,
  required ValueChanged<double> onChanged,
}) {
  var current = initial;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 16),
                Slider(
                  value: current,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: label(current),
                  onChanged: (value) {
                    setState(() => current = value);
                  },
                  onChangeEnd: onChanged,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}