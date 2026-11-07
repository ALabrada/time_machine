import 'package:time_machine_cloud/time_machine_cloud.dart';

/// Native builds never reach this: they use the system-browser OAuth flow.
ProviderAuth createWebProviderAuth({
  required String providerId,
  required Uri backendUrl,
  String? clientId,
}) {
  throw UnsupportedError(
    'Web provider authentication is only available on the web',
  );
}
