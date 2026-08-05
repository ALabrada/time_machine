import 'package:flutter/material.dart';
import 'package:time_machine_res/time_machine_res.dart';

class GallerySearchBar extends StatelessWidget {
  const GallerySearchBar({
    super.key,
    required this.controller,
    this.hintText,
  });

  final TextEditingController controller;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            offset: Offset(0,2),
            blurRadius: 10.0,
            color: shadowColor(context).withValues(alpha: 0.5),
          ),
        ],
      ),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return AnimatedOpacity(
                opacity: controller.text.isEmpty ? 0 : 1,
                duration: Duration(milliseconds: 300),
                child: IconButton(
                  onPressed: controller.clear,
                  icon: Icon(Icons.close),
                ),
              );
            },
          ),
        ).applyDefaults(searchFieldDecoration(context)),
      ),
    );
  }
}
