import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:time_machine_config/domain/cloud_event.dart';
import 'package:time_machine_config/domain/cloud_state.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:url_launcher/url_launcher_string.dart';

final class CloudController extends ValueNotifier<CloudState> {
  CloudController({
    required this.configurationService,
    required this.networkService,
    required this.cloudSyncService,
    this.googleDriveSignIn,
  }) : super(const NotSelectedState()) {
    unawaited(_load());
  }

  final ConfigurationService configurationService;
  final NetworkService networkService;
  final CloudSyncService cloudSyncService;

  /// Runs the Google OAuth consent flow used when activating a
  /// [GoogleDriveCloud]. When null, Google Drive cannot be activated.
  final GoogleDriveSignIn? googleDriveSignIn;

  String? get cloudName => configurationService.cloud;

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
        await _activate();
      case CloudDeactivateEvent():
        await _deactivate();
    }
  }

  Future<void> _load() async {
    value = const LoadingState();
    final cloud = this.cloud;
    if (cloud == null) {
      value = const NotSelectedState();
      return;
    }
    try {
      await cloud.connect();
      value = _stateFor(cloud);
    } catch (error) {
      value = FailedState(error: error);
    }
  }

  Future<void> _activate() async {
    final previous = value;
    final cloud = this.cloud;
    if (cloud == null) {
      return;
    }
    value = const LoadingState();
    try {
      final active = await _authenticate(cloud);
      if (!cloudSyncService.isActive) {
        throw Exception('Cloud activation failed');
      }
      value = _stateFor(active);
    } catch (error) {
      value = previous;
      rethrow;
    }
  }

  Future<CloudBase> _authenticate(CloudBase cloud) async {
    if (cloud is GoogleDriveCloud) {
      final signIn = googleDriveSignIn;
      if (signIn == null) {
        throw UnsupportedError('Google Drive sign-in is not configured');
      }
      final authenticated = await signIn.connect(openBrowser: _openBrowser);
      networkService.clouds[cloudName!] = authenticated;
      await cloudSyncService.setProvider(authenticated);
      return authenticated;
    }
    await cloudSyncService.setProvider(cloud);
    return cloud;
  }

  Future<void> _openBrowser(Uri uri) async {
    final opened = await launchUrlString(uri.toString());
    if (!opened) {
      throw Exception('Could not open the browser');
    }
  }

  Future<void> _deactivate() async {
    final previous = value;
    final cloud = this.cloud;
    if (cloud == null) {
      return;
    }
    value = const LoadingState();
    try {
      await cloudSyncService.setProvider(null);
      if (cloud is SupabaseCloud) {
        await cloud.signOut();
        value = const SupabaseState(isActive: false);
      } else if (cloud is GoogleDriveCloud) {
        await cloud.logout();
        value = const GoogleDriveState(isConnected: false, isActive: false);
      } else {
        value = const NotSelectedState();
      }
    } catch (error) {
      value = previous;
      rethrow;
    }
  }

  CloudState _stateFor(CloudBase cloud) {
    final isActive = cloudSyncService.isActive;
    if (cloud is GoogleDriveCloud) {
      return GoogleDriveState(isConnected: true, isActive: isActive);
    }
    if (cloud is SupabaseCloud) {
      return SupabaseState(userName: cloud.userEmail, isActive: isActive);
    }
    return const NotSelectedState();
  }
}