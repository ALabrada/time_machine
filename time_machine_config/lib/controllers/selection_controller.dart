import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

final class SelectionController<T> extends ValueNotifier<T> {
  SelectionController({
    List<T> elements= const [],
    required T value,
  }) : elements = BehaviorSubject<List<T>>.seeded(elements), super(value);

  final BehaviorSubject<List<T>> elements;
}