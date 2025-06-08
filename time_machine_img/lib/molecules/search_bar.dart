import 'package:flutter/material.dart';
import 'package:time_machine_res/atoms/inputs.dart';
import 'package:time_machine_res/tokens/colors.dart';

class SearchBar extends StatelessWidget {
  const SearchBar({
    super.key,
    required this.controller,
    this.hint,
  });

  final TextEditingController controller;
  final String? hint;

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
          hintText: hint,
        ).applyDefaults(searchFieldDecoration),
      ),
    );
  }
}
