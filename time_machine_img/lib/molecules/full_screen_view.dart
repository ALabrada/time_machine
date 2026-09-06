import 'package:flutter/material.dart';

class FullScreenView extends StatefulWidget {
  const FullScreenView({
    super.key,
    this.topBar,
    this.bottomBar,
    required this.content,
    required this.collapsible,
    required this.animationController,
  });

  final PreferredSizeWidget? topBar;
  final PreferredSizeWidget? bottomBar;
  final Widget? content;
  final bool collapsible;
  final AnimationController animationController;

  @override
  FullScreenViewState createState() => FullScreenViewState();
}

class FullScreenViewState extends State<FullScreenView> {
  @override
  void didUpdateWidget(covariant FullScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsible != widget.collapsible) {
      if (widget.collapsible) {
        // Became collapsible: start from the expanded state.
        widget.animationController.value = 0;
      } else if (widget.animationController.value != 0) {
        // Became non-collapsible while collapsed: animate back to expanded.
        widget.animationController.animateTo(
          0,
          curve: Curves.easeIn,
          duration: const Duration(milliseconds: 300),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.content != null)
          GestureDetector(
            onTap: widget.collapsible ? _toggle : null,
            child: widget.content,
          ),
        if (widget.topBar != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: widget.animationController,
              child: widget.topBar,
              builder: (context, child) {
                final height = widget.topBar?.preferredSize.height ??
                    MediaQuery.of(context).padding.top;
                return Opacity(
                  opacity: 1 - widget.animationController.value,
                  child: Transform.translate(
                    offset:
                        Offset(0, -height * widget.animationController.value),
                    child: child,
                  ),
                );
              },
            ),
          ),
        if (widget.bottomBar != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: widget.animationController,
              child: widget.bottomBar,
              builder: (context, child) {
                final height = widget.bottomBar?.preferredSize.height ??
                    MediaQuery.of(context).padding.bottom;
                return Opacity(
                  opacity: 1 - widget.animationController.value,
                  child: Transform.translate(
                    offset:
                        Offset(0, height * widget.animationController.value),
                    child: child,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _toggle() async {
    if (widget.animationController.value == 0) {
      await widget.animationController.animateTo(1, curve: Curves.easeIn);
    } else {
      await widget.animationController.animateBack(0, curve: Curves.easeIn);
    }
  }
}
