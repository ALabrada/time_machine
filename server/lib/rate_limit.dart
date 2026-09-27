import 'dart:core';

class RateLimiter {
  RateLimiter({
    this.maxRequestsPerWindow = 120,
    this.window = const Duration(minutes: 1),
  });

  final int maxRequestsPerWindow;
  final Duration window;
  final Map<String, _Window> _state = {};

  bool allow(String key) {
    final now = DateTime.now();
    final current = _state[key];
    if (current == null) {
      _state[key] = _Window(now, 1);
      return true;
    }
    if (now.difference(current.startedAt) > window) {
      _state[key] = _Window(now, 1);
      return true;
    }
    if (current.count >= maxRequestsPerWindow) {
      return false;
    }
    current.count++;
    return true;
  }
}

class _Window {
  _Window(this.startedAt, this.count);
  final DateTime startedAt;
  int count;
}