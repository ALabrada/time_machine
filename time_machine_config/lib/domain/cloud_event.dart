abstract class CloudEvent {
  const CloudEvent();
}

class CloudActivateEvent extends CloudEvent {
  const CloudActivateEvent();
}

class CloudDeactivateEvent extends CloudEvent {
  const CloudDeactivateEvent();
}

/// Signs into a Nextcloud instance and activates it. Carries the credentials
/// collected by the UI so that [cloud_controller.CloudController] can perform
/// the authentication; extends [CloudActivateEvent] because a successful
/// sign-in immediately activates the cloud. The [password] may be an app
/// password or the account password; the cloud tries both.
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