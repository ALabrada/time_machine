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