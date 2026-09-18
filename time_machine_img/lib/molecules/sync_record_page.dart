import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/img_localizations.dart';

/// Keeps a page displaying a single [Record] or [Picture] in sync with the
/// database without touching any service or the database: the page's controller
/// owns the monitoring and drives the content through its own stream this mixin
/// never reads. [watchSyncRecord] only subscribes to the controller's deletion
/// stream and navigates home with a toast when the entity disappears.
mixin SyncRecordPage<T extends StatefulWidget> on State<T> {
  static DateTime? _lastDeletedToast;

  StreamSubscription<void>? _deletedSubscription;
  bool _isRecord = false;
  bool _redirected = false;

  /// Starts reacting to the controller's deletion stream.
  /// [isRecord] only selects the toast message.
  void watchSyncRecord({
    required Stream<void> deleted,
    required bool isRecord,
  }) {
    _isRecord = isRecord;
    _redirected = false;

    _deletedSubscription?.cancel();
    _deletedSubscription = deleted.listen((_) {
      _redirectToHome();
    });
  }

  /// Cancels the subscription started by [watchSyncRecord].
  void disposeSyncRecordWatcher() {
    _deletedSubscription?.cancel();
  }

  void _redirectToHome() {
    if (_redirected || !mounted) {
      return;
    }
    _redirected = true;
    if (_lastDeletedToast == null ||
        DateTime.now().difference(_lastDeletedToast!) >
            const Duration(seconds: 3)) {
      _lastDeletedToast = DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isRecord
            ? ImgLocalizations.of(context).recordDeleted
            : ImgLocalizations.of(context).pictureDeleted),
      ));
    }
    context.go('/');
  }
}