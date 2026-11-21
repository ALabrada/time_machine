## 1.1.0

* Shared pure-Dart domain models and helpers used by the app and the proxy
  server.
* `Picture`, `Record`, `Location`, `Area`, `PlaceInfo`, `CloudMetadata` and
  `SyncState` models, plus their `*Mirror` variants.
* `CachedImageFetcher` image cache with a configurable host allow-list,
  memory/disk caching and inline `data:` URL decoding.
* Geo-math and cross-platform file-path helpers.
