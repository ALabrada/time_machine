import 'package:flutter/foundation.dart';
import 'package:time_machine_config/services/configuration_service.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_net/time_machine_net.dart';

final class CloudController extends ChangeNotifier {
  CloudController({
    required this.configurationService,
    required this.networkService,
    required this.cloudSyncService,
  }) {
    connect();
  }

  final ConfigurationService configurationService;
  final NetworkService networkService;
  final CloudSyncService cloudSyncService;

  CloudBase? _cloud;
  bool _loading = false;
  Object? _error;

  String? get cloudName => configurationService.cloud;
  CloudBase? get cloud => _cloud;
  bool get loading => _loading;
  Object? get error => _error;
  bool get isActive => cloudSyncService.isActive;

  bool get cloudAvailable {
    final name = cloudName;
    return name != null && networkService.clouds.containsKey(name);
  }

  bool get supportsAuthentication {
    final cloud = _cloud;
    return cloud is SupabaseCloud;
  }

  bool get isAuthenticated {
    final cloud = _cloud;
    if (cloud is SupabaseCloud) {
      return cloud.isAuthenticated;
    }
    return false;
  }

  Future<void> connect() async {
    final cloudName = configurationService.cloud;
    if (cloudName == null) {
      return;
    }
    final cloud = networkService.clouds[cloudName];
    if (cloud == null) {
      return;
    }
    _setLoading(true);
    try {
      await cloud.connect();
      _cloud = cloud;
      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signIn(String email, String password) async {
    final cloud = _cloud;
    _setLoading(true);
    try {
      if (cloud is SupabaseCloud) {
        await cloud.authenticate(email, password);
      } else {
        throw Exception('No cloud provider available to sign in to.');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    final cloud = _cloud;
    _setLoading(true);
    try {
      if (cloud is SupabaseCloud) {
        await cloud.signOut();
      } else {
        throw Exception('No cloud provider available to sign out from.');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> activate() async {
    final cloud = _cloud;
    if (cloud == null) {
      return false;
    }
    _setLoading(true);
    try {
      await cloudSyncService.setProvider(cloud);
    } finally {
      _setLoading(false);
    }
    return cloudSyncService.isActive;
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
