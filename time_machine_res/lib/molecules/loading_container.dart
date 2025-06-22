import 'dart:async';
import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: color));
  }
}

class LoadingContainer extends StatefulWidget {
  const LoadingContainer({
    super.key,
    required this.child,
    this.overlayOpacity = 1,
  }) : assert(overlayOpacity > 0 && overlayOpacity <= 1);

  final Widget child;
  final double overlayOpacity;

  static LoadingContainerState? of(BuildContext context) {
    return context.findAncestorStateOfType<LoadingContainerState>();
  }

  @override
  State<StatefulWidget> createState() => LoadingContainerState();
}

class LoadingContainerState extends State<LoadingContainer> {
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  set isLoading(bool value) {
    setState(() {
      _isLoading = value;
    });
  }

  void show(String? message) {
    isLoading = true;
  }

  void hide() {
    isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isLoading)
          ModalBarrier(
            dismissible: false,
            color: Theme.of(context).colorScheme.background.withAlpha(128),
          ),
        if (_isLoading)
          Opacity(
            opacity: widget.overlayOpacity,
            child: const LoadingView(),
          ),
      ],
    );
  }
}

extension LoadingExtensions on BuildContext {
  set isLoading(bool value) {
    final containerState = findAncestorStateOfType<LoadingContainerState>();
    containerState?.isLoading = value;
  }

  Future<T> execute<T>(FutureOr<T> Function() task, {String? message}) async {
    final containerState = findAncestorStateOfType<LoadingContainerState>();
    containerState?.show(message);
    try {
      return await task();
    } finally {
      containerState?.hide();
    }
  }
}
