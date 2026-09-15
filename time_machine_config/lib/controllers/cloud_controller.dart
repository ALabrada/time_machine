import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:time_machine_config/domain/cloud_event.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

final class CloudController extends ValueNotifier<CloudState> {
  CloudController({
    required this.configurationService,
    required this.networkService,
    required this.cloudSyncService,
  }) : super(const NotSelectedState()) {
    unawaited(_load());
  }

  final ConfigurationService configurationService;
  final NetworkService networkService;
  final CloudSyncService cloudSyncService;

  String? get cloudName => configurationService.cloud;

  /// The cloud providers available for selection, sorted by name.
  List<String> get cloudNames {
    final names = networkService.clouds.keys.toList();
    names.sort();
    return names;
  }

  CloudBase? get cloud {
    final name = configurationService.cloud;
    if (name == null) {
      return null;
    }
    return networkService.clouds[name];
  }

  bool get cloudAvailable => cloud != null;

  bool get isActive => cloudSyncService.isActive;

  bool get loading => value is LoadingState;

  /// The phase of the ongoing loading operation, when [loading] is true.
  CloudLoadingPhase? get loadingPhase =>
      value is LoadingState ? (value as LoadingState).phase : null;

  /// Selects the configured cloud provider and loads its state. If a
  /// different cloud is currently active, it is deactivated first so no
  /// previous provider keeps syncing.
  void selectCloud(String name) {
    final current = configurationService.cloud;
    if (current == null || current == name) {
      unawaited(_load());
      return;
    }
    unawaited(_changeProvider(name));
  }

  Future<void> _changeProvider(String name) async {
    if (isActive) {
      try {
        await _deactivate();
      } catch (_) {
        // Keep the current cloud configured; do not switch to a new one
        // whose activation was never confirmed.
        return;
      }
    }
    configurationService.cloud = name;
    await _load();
  }

  /// Switches back to the provider selection list.
  void showSelection() {
    value = NotSelectedState(clouds: cloudNames);
  }

  Object? get error {
    final current = value;
    if (current is FailedState) {
      return current.error;
    }
    return null;
  }

  Future<void> handleEvent(CloudEvent event) async {
    switch (event) {
      case CloudActivateEvent():
        await _activate(event);
      case CloudDeactivateEvent():
        await _deactivate();
    }
  }

  Future<void> _load() async {
    value = const LoadingState(phase: CloudLoadingPhase.connecting);
    final cloud = this.cloud;
    if (cloud == null) {
      value = NotSelectedState(clouds: cloudNames);
      return;
    }
    value = _stateFor(cloud);
  }

  Future<void> _activate(CloudActivateEvent event) async {
    final previous = value;
    final cloud = this.cloud;
    if (cloud == null) {
      return;
    }
    value = const LoadingState(phase: CloudLoadingPhase.authenticating);
    try {
      await _authenticate(cloud, event);
      value = const LoadingState(phase: CloudLoadingPhase.synchronizing);
      try {
        await cloudSyncService.setProvider(cloud);
      } catch (error) {
        // The cloud may have persisted a session the server never confirmed;
        // let it log itself out instead of keeping unvalidated credentials.
        await cloud.logout();
        rethrow;
      }
      if (!cloudSyncService.isActive) {
        // CloudSyncService.setProvider swallows initialize() errors, so a
        // freshly stored session may never have been validated. Log the cloud
        // out so the user is not locked to a broken sign-in.
        await cloud.logout();
        throw Exception('Cloud activation failed');
      }
      value = _stateFor(cloud);
    } catch (error) {
      // A failed Nextcloud sign-in restores a non-authenticated state that
      // still carries the remembered credentials, so the form is refilled
      // with the server URL and login name the user just entered.
      value = _stateForAuthFailure(cloud, previous);
      rethrow;
    }
  }

  /// Dispatches the authentication step to the configured cloud. Every
  /// provider exposes its own `authenticate`/`signIn` variant; Nextcloud
  /// additionally carries the submitted credentials on the event.
  Future<void> _authenticate(CloudBase cloud, CloudActivateEvent event) async {
    if (event is NextCloudSignInEvent) {
      if (cloud is! NextCloudCloud) {
        throw StateError(
          'Nextcloud sign-in requires a Nextcloud cloud, '
          'not ${cloud.runtimeType}',
        );
      }
      await cloud.authenticate(
        serverUrl: event.serverUrl,
        loginName: event.loginName,
        password: event.password,
      );
      return;
    }
    // Providers whose session needs no extra credentials here (Supabase fills
    // its own session through its client) need no authentication step.
    if (cloud is DropBoxCloud) {
      await cloud.authenticate();
    } else if (cloud is GoogleDriveCloud) {
      await cloud.authenticate();
    } else if (cloud is YandexDiskCloud) {
      await cloud.authenticate();
    }
  }

  CloudState _stateForAuthFailure(CloudBase cloud, CloudState previous) {
    if (cloud is NextCloudCloud) {
      return NextCloudState(
        serverUrl: cloud.serverUrl,
        loginName: cloud.userEmail,
        isActive: false,
      );
    }
    return previous;
  }

  Future<void> _deactivate() async {
    final previous = value;
    final cloud = this.cloud;
    if (cloud == null) {
      return;
    }
    value = const LoadingState(phase: CloudLoadingPhase.deactivating);
    try {
      await cloudSyncService.setProvider(null);
      await cloud.logout();
      value = _stateForDeactivated(cloud);
    } catch (error) {
      value = previous;
      rethrow;
    }
  }

  CloudState _stateForDeactivated(CloudBase cloud) {
    if (cloud is SupabaseCloud) {
      return const SupabaseState(isActive: false);
    }
    if (cloud is GoogleDriveCloud) {
      return const GoogleDriveState(isConnected: false, isActive: false);
    }
    if (cloud is DropBoxCloud) {
      return const DropBoxState(isActive: false);
    }
    if (cloud is YandexDiskCloud) {
      return const YandexDiskState(isActive: false);
    }
    if (cloud is NextCloudCloud) {
      return NextCloudState(
        serverUrl: cloud.serverUrl,
        loginName: cloud.userEmail,
        isActive: false,
      );
    }
    return NotSelectedState(clouds: cloudNames);
  }

  CloudState _stateFor(CloudBase cloud) {
    final isActive = cloudSyncService.isActive;
    if (cloud is GoogleDriveCloud) {
      return GoogleDriveState(isConnected: true, isActive: isActive);
    }
    if (cloud is SupabaseCloud) {
      return SupabaseState(userName: cloud.userEmail, isActive: isActive);
    }
    if (cloud is DropBoxCloud) {
      return DropBoxState(accountEmail: cloud.userEmail, isActive: isActive);
    }
    if (cloud is YandexDiskCloud) {
      return YandexDiskState(
        accountEmail: cloud.userEmail,
        isActive: isActive,
      );
    }
    if (cloud is NextCloudCloud) {
      return NextCloudState(
        // Only a validated, connected session counts as signed in; the
        // presence of a stored session alone does not authenticate the user.
        signedIn: isActive,
        // A restored session wins; otherwise fall back to the credentials of
        // the last sign-in attempt so the form keeps them.
        serverUrl: cloud.serverUrl,
        loginName: cloud.userEmail,
        isActive: isActive,
      );
    }
    return NotSelectedState(clouds: cloudNames);
  }
}
