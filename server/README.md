# time_machine_server

Proxy backend for the [History Lens](https://github.com/ALabrada/time_machine)
Flutter web build. The browser cannot talk to the historical-photo and
geocoding providers directly (CORS), and OAuth client secrets must never ship
to the client, so the web app routes those calls through this server.

## Features

- **Provider & geocoder proxy** — `findIn`, `findNear`, `fetchPicture`,
  `searchAddress` and `searchCoordinates` forward to the providers and
  geocoders registered in the shared `NetworkService`.
- **OAuth flows** — authorization-code + PKCE consent and token refresh for
  Google Drive, Dropbox and Yandex Disk, with `state` validation and a
  redirect-origin allow-list.
- **Cloud storage proxy** — record and file operations under
  `/api/<provider>/...` for the user's own cloud account, plus change
  notifications over a WebSocket.
- **Image proxy** — `/api/image` fetches remote images, restricted to a
  configurable host allow-list.
- **Telegram publishing** — submits posts as Telegram suggested posts, pending
  channel-admin approval.
- **Static web hosting** — serves the built Flutter web app with single-page
  fallback.
- **Rate limiting** and configurable memory/disk image caches.

## Getting started

Prerequisites: Dart SDK (see `environment` in `pubspec.yaml`).

```sh
cd server
dart pub get
dart run bin/server.dart
```

Configuration is read from `server/config.json` (copy `config.example.json`),
then overridden by environment variables.

## Usage

```sh
# Build the web app first, then serve it and the proxy together
flutter build web
cd server
WEB_BUILD_DIR=../build/web dart run bin/server.dart
```

## Configuration

See `config.example.json` for the full key list. Highlights:

- `PORT`, `HOST` — listen address.
- `GOOGLE_DRIVE_CLIENT_ID_WEB`, `GOOGLE_DRIVE_CLIENT_SECRET_WEB`,
  `DROPBOX_APP_KEY`, `DROPBOX_CLIENT_SECRET`, `YANDEX_CLIENT_ID`,
  `YANDEX_CLIENT_SECRET` — OAuth client credentials.
- `GDRIVE_REDIRECT_URI`, `DROPBOX_REDIRECT_URI`, `YANDEX_REDIRECT_URI`,
  `AUTH_REDIRECT_ORIGINS` — OAuth redirect configuration.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHANNEL_ID` — Telegram publishing.
- `ALLOWED_IMAGE_HOSTS`, `IMAGE_CACHE_DIR`, `IMAGE_CACHE_MEMORY`,
  `IMAGE_CACHE_MAX_BYTES` — image proxy and its caches.
- `RATE_LIMIT_PER_MINUTE`, `TRUST_X_FORWARDED_FOR` — request throttling.
- `VK_MAPS_API_KEY`, `YANDEX_API_KEY`, `GEONAMES_USERNAME` — provider/geocoder
  credentials.
- `WEB_BUILD_DIR` — path to the built Flutter web app.

## Docker

The `Dockerfile` builds a standalone executable and serves the web app:

```sh
docker build -t history-lens-server -f server/Dockerfile .
```

## Additional information

The server is part of the History Lens monorepo. File issues and contribute on
the [GitHub repository](https://github.com/ALabrada/time_machine).
