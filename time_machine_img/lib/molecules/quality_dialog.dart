import 'package:flutter/material.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_img/l10n/img_localizations.dart';

class QualityDialog extends StatefulWidget {
  const QualityDialog({
    super.key,
    required this.frameSize,
    required this.fps,
  });

  final int frameSize;
  final int fps;

  @override
  QualityDialogState createState() => QualityDialogState();
}

class QualityDialogState extends State<QualityDialog> {
  static const _frameSizes = ConfigurationService.frameSizeOptions;
  static const _fpsValues = ConfigurationService.fpsOptions;

  late int _frameSize = widget.frameSize;
  late int _fps = widget.fps;

  void _render() {
    Navigator.of(context).pop((frameSize: _frameSize, fps: _fps));
  }

  Widget _buildResolutionSection(TextStyle? labelStyle, ImgLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.timelapseResolution, style: labelStyle),
        RadioGroup<int>(
          groupValue: _frameSize,
          onChanged: (value) =>
              setState(() => _frameSize = value ?? _frameSize),
          child: Column(
            children: [
              for (final size in _frameSizes)
                RadioListTile<int>(
                  value: size,
                  title: Text(resolutionPClass(size)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFpsSection(TextStyle? labelStyle, ImgLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.timelapseFramesPerSecond, style: labelStyle),
        RadioGroup<int>(
          groupValue: _fps,
          onChanged: (value) => setState(() => _fps = value ?? _fps),
          child: Column(
            children: [
              for (final fps in _fpsValues)
                RadioListTile<int>(
                  value: fps,
                  title: Text(l10n.timelapseFps(fps)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ImgLocalizations.of(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return AlertDialog(
      title: Text(l10n.timelapseQuality),
      content: SingleChildScrollView(
        child: MediaQuery.of(context).orientation == Orientation.portrait
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResolutionSection(labelStyle, l10n),
                  _buildFpsSection(labelStyle, l10n),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildResolutionSection(labelStyle, l10n)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildFpsSection(labelStyle, l10n)),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.timelapseCancel),
        ),
        FilledButton(
          onPressed: _render,
          child: Text(l10n.timelapseApply),
        ),
      ],
    );
  }
}