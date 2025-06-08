import 'package:flutter/material.dart';
import 'package:time_machine_res/atoms/inputs.dart';
import 'package:time_machine_res/tokens/colors.dart';

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            offset: Offset(0,2),
            blurRadius: 10.0,
            color: gray05.withValues(alpha: 0.5),
          ),
        ],
      ),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
        ).applyDefaults(searchFieldDecoration),
      ),
    );
  }
}
