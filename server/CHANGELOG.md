## 0.1.0

* Initial release of the History Lens proxy backend for the Flutter web build.
* Proxy the photo-provider and geocoder network calls the browser cannot make
  directly (CORS): `findIn`, `findNear`, `fetchPicture`, `searchAddress` and
  `searchCoordinates`.
* OAuth authorization-code + PKCE consent and token-refresh flows for Google
  Drive, Dropbox and Yandex Disk, with `state` validation and a redirect-origin
  allow-list.
* Cloud storage proxy for the signed-in user's own account: record and file
  operations plus change notifications over a WebSocket.
* Image proxy (`/api/image`) restricted to a configurable host allow-list.
* Telegram publishing submitted as suggested posts, pending channel-admin
  approval.
* Serve the built Flutter web app as static files with single-page fallback.
* Per-client rate limiting and configurable memory/disk image caches.
