abstract class CloudState {
  const CloudState();
}

class NotSelectedState extends CloudState {
  const NotSelectedState();
}

class LoadingState extends CloudState {
  const LoadingState();
}

class FailedState extends CloudState {
  final Object error;

  const FailedState({required this.error,});
}

class GoogleDriveState extends CloudState {
  final bool isConnected;
  final bool isActive;

  const GoogleDriveState({
    required this.isConnected,
    required this.isActive,
  });
}

class SupabaseState extends CloudState {
  final String? userName;
  final bool isActive;

  const SupabaseState({this.userName, required this.isActive,});
}

class DropBoxState extends CloudState {
  final String? accountEmail;
  final bool isActive;

  const DropBoxState({this.accountEmail, required this.isActive});
}

class NextCloudState extends CloudState {
  /// Whether the user is currently authenticated with the provider. This is
  /// only true while the cloud is actually connected, i.e. after a sign-in has
  /// been validated. The mere presence of stored/or remembered [serverUrl] and
  /// [loginName] does NOT mark the user as signed in: those fields instead
  /// carry the credentials of the last attempt (or stored session) so the
  /// sign-in form can be repopulated after a change of state.
  final bool signedIn;
  final String? serverUrl;
  final String? loginName;
  final bool isActive;

  const NextCloudState({
    this.signedIn = false,
    this.serverUrl,
    this.loginName,
    required this.isActive,
  });
}