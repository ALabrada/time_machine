# time_machine_sources

Pure-Dart external content layer for History Lens: the `NetworkService`
registry, historical-photo providers, geocoders and the Telegram publisher.
Shared by the Flutter app and the proxy server.

## Contents

- **NetworkService** — the registry used to look up providers and geocoders.
- **Photo providers** — PastVu, RePhotos, HistoryPin, SepiaTown and
  Russia in Photo.
- **Geocoders** — Geonames, OSM, VKMaps and Yandex.
- **Telegram** — publisher that submits posts as Telegram suggested posts.

## Usage

Add `time_machine_sources` as a path dependency and import
`package:time_machine_sources/time_machine_sources.dart`.

## Additional information

Part of the History Lens monorepo — see the
[GitHub repository](https://github.com/ALabrada/time_machine).
