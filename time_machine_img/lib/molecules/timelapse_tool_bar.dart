import 'package:flutter/material.dart';

import 'tool_bar.dart';

class TimelapseToolBar extends StatefulWidget {
  const TimelapseToolBar({
    super.key,
    required this.animationController,
  });

  final AnimationController animationController;

  @override
  TimelapseToolBarState createState() => TimelapseToolBarState();
}

class TimelapseToolBarState extends State<TimelapseToolBar> {
  bool _repeat = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (context, _) {
        final controller = widget.animationController;
        final primary = Theme.of(context).colorScheme.primary;
        final onSecondary = Theme.of(context).colorScheme.onSecondary;
        return ToolBar(
          children: [
            ListenableBuilder(
              listenable: widget.animationController,
              builder: (context, _) {
                return IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    controller.isAnimating ? Icons.pause : Icons.play_arrow,
                  ),
                );
              },
            ),
            Expanded(
              child: SizedBox(
            height: 24,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: primary,
                    inactiveTrackColor: onSecondary.withValues(alpha: 0.3),
                    thumbColor: primary,
                    overlayColor: primary.withValues(alpha: 0.2),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: controller.value,
                    onChanged: (value) {
                      controller.value = value;
                    },
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _setRepeat(!_repeat),
              icon: Icon(Icons.repeat),
              color: _repeat ? primary : null,
            ),
          ],
        );
      },
    );
  }

  void _togglePlayback() {
    final controller = widget.animationController;
    if (controller.isAnimating) {
      controller.stop();
    } else if (_repeat) {
      controller.repeat(reverse: true);
    } else {
      if (controller.value >= 1.0) {
        controller.value = 0.0;
      }
      controller.forward();
    }
  }

  void _setRepeat(bool repeat) {
    setState(() => _repeat = repeat);
    final controller = widget.animationController;
    if (!controller.isAnimating) {
      return;
    }
    controller.stop();
    if (repeat) {
      controller.repeat(reverse: true);
    } else {
      controller.forward();
    }
  }
}