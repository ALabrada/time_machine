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

  /// The Nextcloud server URL and login name from the last sign-in attempt
  /// (successful or not), kept so the form can be repopulated after a change
  /// of state instead of wiping what the user typed.
  String? _nextcloudServerUrl;
  String? _nextcloudLoginName;

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
      // Must be matched before CloudActivateEvent because it extends it.
      case NextCloudSignInEvent(
          :final serverUrl,
          :final loginName,
          :final password
        ):
        _nextcloudServerUrl = serverUrl;
        _nextcloudLoginName = loginName;
        await _activate(
          serverUrl: serverUrl,
          loginName: loginName,
          password: password,
        );
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

  Future<void> _activate({
    String? serverUrl,
    String? loginName,
    String? password,
  }) async {
    final previous = value;
    final cloud = this.cloud;
    if (cloud == null) {
      return;
    }
    value = const LoadingState();
    try {
      final active = await _authenticate(
        cloud,
        serverUrl: serverUrl,
        loginName: loginName,
        password: password,
      );
      if (!cloudSyncService.isActive) {
        // CloudSyncService.setProvider swallows initialize() errors (it only
        // logs them), so a Nextcloud session may have been stored without
        // ever being validated against the server. Clear it, otherwise the
        // stored server URL and login name could later be mistaken for a
        // valid sign-in.
        if (cloud is NextCloudCloud) {
          await cloud.tokenStore.clear();
        }
        throw Exception('Cloud activation failed');
      }
      value = _stateFor(active);
    } catch (error) {
      // A failed Nextcloud sign-in restores a non-authenticated state that
      // still carries the remembered credentials, so the form is refilled
      // with the server URL and login name the user just entered.
      value = cloud is NextCloudCloud
          ? NextCloudState(
              serverUrl: _nextcloudServerUrl,
              loginName: _nextcloudLoginName,
              isActive: false,
            )
          : previous;
      rethrow;
    }
  }

  Future<CloudBase> _authenticate(
    CloudBase cloud, {
    String? serverUrl,
    String? loginName,
    String? password,
  }) async {
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
    if (cloud is DropBoxCloud) {
      final session = await DropBoxCloud.authorize(
        clientId: cloud.clientId,
        redirectUri: cloud.redirectUri,
      );
      await cloud.tokenStore.write(session);
    }
    var storedSession = false;
    if (cloud is NextCloudCloud) {
      final url = serverUrl;
      final user = loginName;
      final pwd = password;
      if (url != null && user != null && pwd != null) {
        final session = await NextCloudCloud.authorize(
          serverUrl: url,
          loginName: user,
          password: pwd,
        );
        await cloud.tokenStore.write(session);
        storedSession = true;
      }
    }
    try {
      await cloudSyncService.setProvider(cloud);
    } catch (error) {
      // A freshly stored Nextcloud session was not validated yet; if the
      // server rejects it, drop it so the user can re-enter their data
      // instead of being locked to a broken session.
      if (storedSession && cloud is NextCloudCloud) {
        await cloud.tokenStore.clear();
      }
      rethrow;
    }
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
      } else if (cloud is DropBoxCloud) {
        await cloud.logout();
        value = const DropBoxState(isActive: false);
      } else if (cloud is NextCloudCloud) {
        await cloud.logout();
        value = NextCloudState(
          serverUrl: _nextcloudServerUrl,
          loginName: _nextcloudLoginName,
          isActive: false,
        );
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
    if (cloud is DropBoxCloud) {
      return DropBoxState(accountEmail: cloud.userEmail, isActive: isActive);
    }
    if (cloud is NextCloudCloud) {
      return NextCloudState(
        // Only a validated, connected session counts as signed in; the
        // presence of a stored session alone does not authenticate the user.
        signedIn: isActive,
        // A restored session wins; otherwise fall back to the credentials of
        // the last sign-in attempt so the form keeps them.
        serverUrl: cloud.serverUrl ?? _nextcloudServerUrl,
        loginName: cloud.userEmail ?? _nextcloudLoginName,
        isActive: isActive,
      );
    }
    return const NotSelectedState();
  }
}