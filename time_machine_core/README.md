# time_machine_core

Pure-Dart domain models and shared helpers for History Lens, used by both the
Flutter app and the proxy server.

## Contents

- **Domain models** — `Picture`, `Record`, `Location`, `Area`, `PlaceInfo`,
  `CloudMetadata` and `SyncState`, plus their `*Mirror` variants.
- **Image cache** — `CachedImageFetcher` downloads remote images behind a
  configurable host allow-list, decodes inline `data:` URLs and caches in
  memory and on disk.
- **Geo math** — distance and bounding helpers shared by providers and
  geocoders.
- **File paths** — cross-platform path helpers.

## Usage

Add `time_machine_core` as a path dependency and import
`package:time_machine_core/time_machine_core.dart`.

## Additional information

Part of the History Lens monorepo — see the
[GitHub repository](https://github.com/ALabrada/time_machine).
