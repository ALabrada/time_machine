import 'package:flutter/material.dart';

class FullScreenView extends StatelessWidget {
  const FullScreenView({
    super.key,
    this.topBar,
    this.bottomBar,
    required this.content,
    required this.animationController,
  });

  final PreferredSizeWidget? topBar;
  final PreferredSizeWidget? bottomBar;
  final Widget? content;
  final AnimationController animationController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (content != null)
          GestureDetector(
            onTap: () async {
              if (animationController.value == 0) {
                await animationController.animateTo(1, curve: Curves.easeIn);
              } else {
                await animationController.animateBack(0, curve: Curves.easeIn);
              }
            },
            child: content,
          ),
        if (topBar != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: animationController,
              child: topBar,
              builder: (context, child) {
                final height = topBar?.preferredSize.height ?? MediaQuery.of(context).padding.top;
                return Opacity(
                  opacity: 1 - animationController.value,
                  child: Transform.translate(
                    offset: Offset(0, -height * animationController.value),
                    child: child,
                  ),
                );
              },
            ),
          ),
        if (bottomBar != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: animationController,
              child: bottomBar,
              builder: (context, child) {
                final height = bottomBar?.preferredSize.height ?? MediaQuery.of(context).padding.bottom;
                return Opacity(
                  opacity: 1 - animationController.value,
                  child: Transform.translate(
                    offset: Offset(0, height * animationController.value),
                    child: child,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
