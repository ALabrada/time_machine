import 'dart:collection';

class RateLimiter {
  RateLimiter({
    this.maxRequestsPerWindow = 120,
    this.window = const Duration(minutes: 1),
    this.maxTrackedKeys = 10000,
  });

  final int maxRequestsPerWindow;
  final Duration window;

  /// Upper bound on distinct client keys held at once. When the map is full,
  /// expired windows are pruned and, if still full, the least-recently-used
  /// entries are evicted. This keeps a flood of spoofed keys (for example
  /// random `X-Forwarded-For` values) from growing memory without bound.
  final int maxTrackedKeys;

  final LinkedHashMap<String, _Window> _state = LinkedHashMap();

  bool allow(String key) {
    final now = DateTime.now();
    final current = _state[key];
    if (current == null) {
      _ensureCapacity(now);
      _state[key] = _Window(now, 1);
      return true;
    }
    if (now.difference(current.startedAt) > window) {
      // Window elapsed: refresh the entry and move it to the most-recent
      // position so eviction keeps working like an LRU.
      _state.remove(key);
      _state[key] = _Window(now, 1);
      return true;
    }
    if (current.count >= maxRequestsPerWindow) {
      return false;
    }
    current.count++;
    return true;
  }

  void _ensureCapacity(DateTime now) {
    if (_state.length < maxTrackedKeys) {
      return;
    }
    // Prune expired windows first; drop the oldest (least-recently-used)
    // entries only if the map is still at capacity.
    _state.removeWhere((_, w) => now.difference(w.startedAt) > window);
    while (_state.length >= maxTrackedKeys) {
      _state.remove(_state.keys.first);
    }
  }
}

class _Window {
  _Window(this.startedAt, this.count);
  final DateTime startedAt;
  int count;
}
