abstract class CloudEvent {
  const CloudEvent();
}

class CloudActivateEvent extends CloudEvent {
  const CloudActivateEvent();
}

class CloudDeactivateEvent extends CloudEvent {
  const CloudDeactivateEvent();
}

/// Carries the credentials collected by the Nextcloud sign-in form.
/// Extends [CloudActivateEvent] because a successful sign-in immediately
/// activates the cloud.
class NextCloudSignInEvent extends CloudActivateEvent {
  const NextCloudSignInEvent({
    required this.serverUrl,
    required this.loginName,
    required this.password,
  });

  final String serverUrl;
  final String loginName;
  final String password;
}
