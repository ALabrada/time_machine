import 'package:flutter/material.dart';

final class SelectableItem<T> extends ValueNotifier<bool> {
  SelectableItem({
    this.title,
    required this.item,
    bool value = false,
  }) : super(value);

  final String? title;
  final T item;
}