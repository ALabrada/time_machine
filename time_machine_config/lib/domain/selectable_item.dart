import 'package:flutter/material.dart';

final class SelectableItem<T> extends ValueNotifier<bool> {
  SelectableItem({
    required this.item,
    bool value = false,
  }) : super(value);

  final T item;
}