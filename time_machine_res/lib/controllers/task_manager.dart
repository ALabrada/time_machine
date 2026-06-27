import 'dart:async';
import 'package:rxdart/rxdart.dart';

mixin TaskManager {
  final isProcessing = BehaviorSubject<bool>.seeded(false);

  void dispose() {
    isProcessing.close();
  }

  Future<T> execute<T>(FutureOr<T> Function() operation) async {
    isProcessing.value = true;
    try {
      return await operation();
    } finally {
      isProcessing.value = false;
    }
  }
}