# time_machine_sources

Pure-Dart external content layer shared by the History Lens app and the proxy
server.

- `services/network_service.dart` — `NetworkService`, the registry that ties
  geocoders and photo providers together, plus their `DataProvider` and
  `GeocodingService` contracts.
- `services/providers` — historical photo providers (PastVu, Retro Photos,
  Historypin, Russia in Photo, SepiaTown).
- `services/geocoders` — forward and reverse geocoding backends (OSM/Nominatim,
  GeoNames, VK Maps, Yandex).
- `services/telegram_service.dart` — submits suggested posts to a Telegram
  channel.

Models and shared helpers live in `time_machine_core`; cloud-storage backends
live in `time_machine_cloud`.
