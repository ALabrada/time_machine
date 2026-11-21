import 'cloud_base.dart';

/// The set of cloud-storage backends configured for this app instance.
///
/// Kept separate from the provider/geocoder [NetworkService] so the core
/// networking layer does not depend on cloud storage.
class CloudService {
  const CloudService({required this.clouds});

  /// Configured backends keyed by the provider id used in the configuration
  /// (for example `dropbox`, `gdrive`, `nextcloud` or `yandex`).
  final Map<String, CloudBase> clouds;
}
