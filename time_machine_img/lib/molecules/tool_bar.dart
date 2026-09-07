import 'package:flutter/material.dart';

class ToolBar extends StatelessWidget {
  const ToolBar({
    super.key,
    required this.children,
    this.decoration,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final BoxDecoration? decoration;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoration ?? BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: padding,
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: children,
    );
  }
}
