import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Live view of the most recently produced interpolated frame while rendering,
/// shown as a single frame glued onto a videotape strip that glides to the
/// frame's temporal position within the whole sequence.
class FrameView extends StatelessWidget {
  final Uint8List frame;
  final int frameIndex;
  final int totalFrames;

  /// The trackbar spans this fraction of the available width.
  final double widthFactor;

  const FrameView({
    super.key,
    required this.frame,
    required this.frameIndex,
    required this.totalFrames,
    this.widthFactor = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: FrameSequenceIndicator(
        frame: frame,
        frameIndex: frameIndex,
        totalFrames: totalFrames,
      ),
    );
  }
}

/// An old-school videotape strip. The current frame is glued onto it, taller
/// than the tape, and glides from its previous temporal position to the new one
/// as each out-of-order frame is produced.
class FrameSequenceIndicator extends StatefulWidget {
  final Uint8List frame;
  final int frameIndex;
  final int totalFrames;

  const FrameSequenceIndicator({
    super.key,
    required this.frame,
    required this.frameIndex,
    required this.totalFrames,
  });

  @override
  State<FrameSequenceIndicator> createState() => _FrameSequenceIndicatorState();
}

class _FrameSequenceIndicatorState extends State<FrameSequenceIndicator>
    with SingleTickerProviderStateMixin {
  static const _tapeHeight = 16.0;
  static const _frameSize = 64.0;
  static const _sprocketSize = 3.0;
  static const _totalHeight = _frameSize + 8.0;

  late final AnimationController _controller;
  late Animation<double> _animation;
  late double _target;

  @override
  void initState() {
    super.initState();
    _target = _fraction();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..value = _target;
    _animation = _controller;
  }

  double _fraction() => widget.totalFrames <= 1
      ? 0.0
      : widget.frameIndex / (widget.totalFrames - 1);

  @override
  void didUpdateWidget(covariant FrameSequenceIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newTarget = _fraction();
    if (newTarget == _target) return;
    final from = _target;
    _target = newTarget;
    _animation = Tween(begin: from, end: newTarget).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _totalHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colorScheme = Theme.of(context).colorScheme;
          final trackWidth = constraints.maxWidth;
          final tapeTop = (_totalHeight - _tapeHeight) / 2;
          final numSprockets = (trackWidth / (_sprocketSize + 5)).floor();
          return Stack(
            children: [
              _TapeBody(height: _tapeHeight, top: tapeTop),
              _SprocketRow(
                count: numSprockets,
                top: tapeTop + 2,
                surfaceColor: colorScheme.surface,
              ),
              _SprocketRow(
                count: numSprockets,
                top: tapeTop + _tapeHeight - _sprocketSize - 2,
                surfaceColor: colorScheme.surface,
              ),
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => _buildCurrentFrame(
                  context,
                  trackWidth,
                  _animation.value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentFrame(
      BuildContext context, double trackWidth, double fraction) {
    final colorScheme = Theme.of(context).colorScheme;
    final left = fraction * (trackWidth - _frameSize);
    return Positioned(
      left: left,
      top: (_totalHeight - _frameSize) / 2,
      child: Container(
        width: _frameSize,
        height: _frameSize,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.secondary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Image.memory(
          widget.frame,
          width: _frameSize,
          height: _frameSize,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

/// The brown magnetic tape strip with a subtle vertical sheen.
class _TapeBody extends StatelessWidget {
  final double height;
  final double top;

  const _TapeBody({required this.height, required this.top});

  static const _colors = [
    Color(0xFF6B4E3D),
    Color(0xFF5C4033),
    Color(0xFF452E22),
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _colors,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// A row of small punched holes running along one edge of the tape.
class _SprocketRow extends StatelessWidget {
  final int count;
  final double top;
  final Color surfaceColor;

  const _SprocketRow({
    required this.count,
    required this.top,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          count,
          (_) => Container(
            width: _FrameSequenceIndicatorState._sprocketSize,
            height: _FrameSequenceIndicatorState._sprocketSize,
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(0.5),
            ),
          ),
        ),
      ),
    );
  }
}
