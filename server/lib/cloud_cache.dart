import 'dart:async';

import 'package:time_machine_cloud/services/cloud_base.dart';

/// Creates and initializes a cloud for [provider] using [token].
typedef CloudFactory = Future<CloudInit> Function(
  String provider,
  String token, {
  bool startPolling,
});

/// A freshly initialized cloud and the provider-specific id returned by
/// `initialize()` (for example `dropbox/user@example.com`).
class CloudInit {
  CloudInit(this.cloud, this.id);

  final CloudBase cloud;
  final String id;
}

class _CloudEntry {
  _CloudEntry(this.cloud, this.id);

  final CloudBase cloud;
  final String id;

  /// Number of leases currently using this entry (sockets and HTTP requests).
  int refs = 0;
  bool disposed = false;
}

/// A borrowed cloud.
///
/// Temporary leases dispose their cloud on release. Cached leases drop a
/// reference and dispose the entry when the last user is gone.
class CloudLease {
  CloudLease._(
    this._cache,
    this._key,
    this._entry, {
    required bool temporary,
  }) : _temporary = temporary;

  final CloudCache _cache;
  final String _key;
  final _CloudEntry _entry;
  final bool _temporary;
  bool _released = false;

  CloudBase get cloud => _entry.cloud;
  String get id => _entry.id;

  void release() {
    if (_released) return;
    _released = true;
    if (_temporary) {
      _entry.disposed = true;
      _entry.cloud.dispose();
      return;
    }
    _entry.refs--;
    if (_entry.refs <= 0) {
      _cache._remove(_key, _entry);
      _entry.disposed = true;
      _entry.cloud.dispose();
    }
  }
}

/// Caches one cloud per (provider, browser session token) while at least one
/// changes socket or in-flight HTTP request is using it.
///
/// The browser's changes socket keeps the entry alive between requests; once
/// the socket and all requests are gone the cloud is disposed, so idle
/// sessions do not accumulate in memory. A request that arrives without a
/// cached entry gets a temporary cloud that is disposed when the request ends.
class CloudCache {
  CloudCache(this._create);

  final CloudFactory _create;
  final Map<String, _CloudEntry> _entries = {};
  final Map<String, Future<CloudInit>> _pending = {};

  String _key(String provider, String token) => '$provider\u0000$token';

  /// Acquires a cloud for one HTTP request or for a browser's changes socket.
  ///
  /// [anchor] should be true for the long-lived changes socket. Only anchored
  /// entries are cached; HTTP requests reuse them when present.
  Future<CloudLease> acquire(
    String provider,
    String token, {
    bool anchor = false,
  }) async {
    final key = _key(provider, token);
    final existing = _entries[key];
    if (existing != null && !existing.disposed) {
      existing.refs++;
      return CloudLease._(this, key, existing, temporary: false);
    }

    if (!anchor) {
      // Join an in-flight socket initialization instead of creating a second
      // cloud when the first HTTP request races the changes socket.
      final pending = _pending[key];
      if (pending != null) {
        await pending;
        final created = _entries[key];
        if (created != null && !created.disposed) {
          created.refs++;
          return CloudLease._(this, key, created, temporary: false);
        }
      }
      final init = await _create(provider, token);
      return CloudLease._(
        this,
        key,
        _CloudEntry(init.cloud, init.id),
        temporary: true,
      );
    }

    final pending = _pending[key];
    if (pending != null) {
      await pending;
      final created = _entries[key];
      if (created != null && !created.disposed) {
        created.refs++;
        return CloudLease._(this, key, created, temporary: false);
      }
    }

    final future = _create(provider, token, startPolling: true);
    _pending[key] = future;
    try {
      final init = await future;
      final entry = _CloudEntry(init.cloud, init.id)..refs = 1;
      _entries[key] = entry;
      return CloudLease._(this, key, entry, temporary: false);
    } finally {
      _pending.remove(key);
    }
  }

  void _remove(String key, _CloudEntry entry) {
    if (identical(_entries[key], entry)) {
      _entries.remove(key);
    }
  }
}
