import 'package:flutter/material.dart';

class ToolBar extends StatelessWidget {
  const ToolBar({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.secondary,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
      ),
    );
  }
}
